/*
 * Copyright (C) 2021-2026, 5DPLAY Game Studio
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

package net.play5d.game.bvn.ctrler.lan {
import flash.utils.ByteArray;
import flash.utils.Endian;

import net.play5d.game.bvn.MainGame;
import net.play5d.game.bvn.ctrler.game_ctrls.GameCtrl;
import net.play5d.game.bvn.data.lan.LanNetConfig;
import net.play5d.game.bvn.data.lan.LanRelayTick;
import net.play5d.game.bvn.data.vos.GameRunDataVO;
import net.play5d.game.bvn.events.GameEvent;
import net.play5d.game.bvn.input.GameSocketInput;
import net.play5d.game.bvn.interfaces.lan.ILanRelayLockLink;
import net.play5d.game.bvn.stage.GameStage;
import net.play5d.kyo.stage.IStage;

/**
 * 锁帧算法（中继定帧，对称，双方各创建一份）。
 *
 * <p>对局中由中继按固定节拍下发每帧的 <code>[p1K, p2K]</code>；本机经抖动缓冲，
 * 每次 <code>render</code> 严格推进 1 帧并把 <code>p1K</code> / <code>p2K</code> 写回
 * P1 / P2 输入通道，双方因此逐帧输入一致、模拟一致。每次 <code>render</code> 向中继上报
 * 本机输入与已推进帧号。缓冲耗尽则停顿并重新缓冲，不做追帧（逻辑不可在同一 ENTER_FRAME 内重复步进）。</p>
 *
 * <p>战斗段（整场对局）生命周期由本类监听 <code>GameEvent</code> 自行驱动：
 * <code>GAME_START</code>（<code>GameCtrl.doStartGame</code> 内，对战构建完成后、首次渲染注册之前）
 * 序号递增、清空帧缓冲并发送 <code>CMD_START</code>；回合之间不停止、不重启，
 * 开场、KO、回合切换动画全部随中继帧推进；<code>GAME_END</code>（终局结算完成、离开对战场景前）
 * 或 <code>dispose</code> 发送 <code>CMD_STOP</code>。战斗段内首帧到达前 <code>render</code> 返回
 * <code>false</code>（双方画面冻结在同一状态），无自由播放。</p>
 *
 * <p>房主（<code>localIsP1</code>）仍经 <code>LanServerSyncCore</code> 下发 SYNC 消息，并以中继帧号为准：
 * 回合 / 结束消息经 <code>runAtFrame</code> 延后到客户端播放至同一帧（双方确定性模拟时通常已各自结算，
 * 该消息仅作兜底）；状态快照由房主按帧号
 * 经 <code>snapshotSender</code> 发出，客户端经 <code>receiveSyncUpdate</code> 接收并在该帧应用。
 * 房主自身不应用快照。</p>
 *
 * @see ILanLockFrame
 * @see net.play5d.game.bvn.interfaces.lan.ILanRelayLockLink
 * @see net.play5d.game.bvn.data.lan.LanRelayTick
 */
public class LockFrameRelayLogic implements ILanLockFrame {
    /**
     * 构造中继定帧锁帧逻辑。
     */

    /**
     * 兼容 <code>ILanLockFrame</code>；中继定帧忽略该值，由战斗段自行管理。
     * @default true
     */
    public var enabled:Boolean = true;

    /**
     * 卡顿监视；壳可设置其 <code>onStall</code> / <code>onResume</code> / <code>onTimeout</code>。
     */
    public var stallMonitor:LanStallMonitor = new LanStallMonitor();

    /**
     * 客户端侧同步内核；快照回合不符或应用失败时经其 <code>syncError</code> 上报，成功则 <code>resetSyncError</code>。可为 null。
     */
    public var syncCore:LanClientSyncCore;

    /**
     * 房主侧快照发送函数，签名 <code>Function(snapshot:ByteArray):void</code>；为 null 时不发快照。
     * 仅 <code>localIsP1</code> 的一方会调用。
     */
    public var snapshotSender:Function;

    /**
     * 失步检测回调，签名 <code>function(epoch:uint, frame:uint, hash:uint, detail:String):void</code>。
     * 战斗段内每推进 <code>LanNetConfig.HASH_INTERVAL</code> 帧，在该帧模拟完成后
     * （即下一次 <code>render</code> 入口、尚未推进下一帧前）双方同点各调用一次；为 null 时不计算。
     */
    public var onStateHash:Function;

    /** @private */
    private var _link:ILanRelayLockLink;
    /** @private */
    private var _local:GameSocketInput;
    /** @private */
    private var _inputP1:GameSocketInput;
    /** @private */
    private var _inputP2:GameSocketInput;
    /** @private */
    private var _localIsP1:Boolean;
    /** @private 当前是否处于战斗段（整场对局；已发送 START 且未 STOP） */
    private var _active:Boolean;
    /** @private */
    private var _epoch:uint;
    /** @private 已推进的帧号 */
    private var _frame:int;
    /** @private 已连续收到的最大帧号 */
    private var _head:int;
    /** @private 帧号 -> [p1K, p2K] */
    private var _pairs:Object = {};
    /** @private */
    private var _started:Boolean;
    /** @private 待到帧应用的快照（帧号 -> 快照） */
    private var _snaps:Object = {};
    /** @private 距上次发快照的帧数 */
    private var _syncCount:int;
    /** @private 待到帧执行的房主消息回调（按到达顺序） */
    private var _finishFns:Array = [];
    /** @private 与 <code>_finishFns</code> 对应的房主帧号 */
    private var _finishFrames:Array = [];
    /** @private 已上报过哈希的帧号 */
    private var _hashedFrame:int;

    /**
     * 注入会话与输入通道，并开始监听战斗段事件。
     *
     * @param link 中继会话。
     * @param localInput 本机采集输入的通道（通常与 <code>inputP1</code> / <code>inputP2</code> 之一为同一对象）。
     * @param inputP1 P1 Socket 输入。
     * @param inputP2 P2 Socket 输入。
     * @param localIsP1 本机是否为 P1（房主）。
     */
    public function init(
            link      :ILanRelayLockLink,
            localInput:GameSocketInput,
            inputP1   :GameSocketInput,
            inputP2   :GameSocketInput,
            localIsP1 :Boolean
    ):void {
        removeEvents();
        _link      = link;
        _local     = localInput;
        _inputP1   = inputP1;
        _inputP2   = inputP2;
        _localIsP1 = localIsP1;

        GameEvent.addEventListener(GameEvent.GAME_START, onGameStart);
        GameEvent.addEventListener(GameEvent.GAME_END, onGameEnd);
    }

    /**
     * 兼容 <code>ILanLockFrame</code>：设置 <code>enabled</code>。
     * @param v 是否参与渲染推进。
     */
    public function setEnabled(v:Boolean):void {
        enabled = v;
    }

    /**
     * 兼容 <code>ILanLockFrame</code>；战斗段由本类自行重置，此处仅清卡顿状态。
     */
    public function reset():void {
        stallMonitor.reset();
    }

    /**
     * 本机已推进到的中继帧号。
     */
    public function get frame():int {
        return _frame;
    }

    /**
     * 当前战斗段序号（每场对局递增，从 1 开始；双方对局数一致故序号一致）。
     */
    public function get epoch():uint {
        return _epoch;
    }

    /**
     * 抖动缓冲中尚未播放的帧数（可供壳显示）。
     */
    public function get bufferedFrames():int {
        return _head - _frame;
    }

    /**
     * 本机推进到中继帧 <code>hostFrame</code> 之后再执行回调；已到达或不在战斗段时立即执行。
     *
     * @param hostFrame 房主事件发生时的中继帧号。
     * @param fn 无参回调。
     */
    public function runAtFrame(hostFrame:int, fn:Function):void {
        if (!_active || _frame >= hostFrame) {
            fn();

            return;
        }

        _finishFrames.push(hostFrame);
        _finishFns.push(fn);
    }

    /**
     * 释放引用并移除事件监听；战斗段进行中会发送 STOP。
     */
    public function dispose():void {
        removeEvents();
        endSegment();
        stallMonitor.dispose();
        _pairs         = {};
        _snaps         = {};
        _finishFns     = [];
        _finishFrames  = [];
        syncCore       = null;
        snapshotSender = null;
        onStateHash    = null;
        _link          = null;
        _local         = null;
        _inputP1       = null;
        _inputP2       = null;
    }

    /**
     * 处理中继 TICK_FRAME。
     *
     * @param payload 载荷（不含 3 字节帧头）：<code>u32 startFrame, u8 count, count * (i16 p1K, i16 p2K)</code>。
     */
    public function receiveTickFrame(payload:ByteArray):void {
        if (!_active || !payload || payload.length < 5) {
            return;
        }

        payload.endian   = Endian.BIG_ENDIAN;
        payload.position = 0;

        var start:uint = payload.readUnsignedInt();
        var count:int  = payload.readUnsignedByte();
        var f:int;
        var k1:int;
        var k2:int;
        for (var i:int = 0; i < count && payload.bytesAvailable >= 4; i++) {
            k1 = payload.readShort();
            k2 = payload.readShort();
            f  = start + i;
            if (f > _frame && !_pairs[f]) {
                _pairs[f] = [k1, k2];
            }
        }

        while (_pairs[_head + 1]) {
            _head++;
        }
    }

    /**
     * 处理房主下发的状态快照（仅客户端）；到达本机播放至该帧时应用。
     *
     * @param msgArr 完整载荷（含 type 首字节）。
     * @return 已识别时为 <code>true</code>。
     */
    public function receiveSyncUpdate(msgArr:ByteArray):Boolean {
        var snap:LanInputSyncSnapshot = LanInputSyncCodec.decode(msgArr);
        if (!snap) {
            return false;
        }
        if (_active && snap.frame > _frame) {
            _snaps[snap.frame] = snap;
        }

        return true;
    }

    /**
     * 每帧推进；缓冲不足时返回 <code>false</code>。
     * @return 是否允许本帧游戏逻辑推进。
     */
    public function render():Boolean {
        var go:Boolean = renderFrame();
        stallMonitor.update(!go && _active);

        return go;
    }

    /** @private */
    private function renderFrame():Boolean {
        if (!_active) {
            return true;
        }

        reportStateHash();
        sendLocalInput();

        // 兜底：房主消息所指帧已到而本机尚未自行结算时执行；整场对局为同一战斗段，不在此结束
        while (_active && _finishFns.length > 0 && _frame >= _finishFrames[0]) {
            _finishFrames.shift();
            (_finishFns.shift() as Function)();
        }

        if (!_active) {
            return false;
        }

        var buffered:int = _head - _frame;
        var need:int     = _finishFns.length > 0 ? 1 : Math.max(1, LanNetConfig.relayBufferFrames);
        if (buffered < 1 || (!_started && buffered < need)) {
            _started = false;

            return false;
        }

        _started = true;
        _frame++;

        var pair:Array = _pairs[_frame];
        delete _pairs[_frame];

        if (_localIsP1) {
            sendSnapshot();
        }
        else {
            applyPendingSnapshot();
        }

        _inputP1.setSocketData(pair[0]);
        _inputP2.setSocketData(pair[1]);

        return true;
    }

    /**
     * @private 已推进到间隔帧且该帧已模拟完成时上报状态哈希（只读，每段每间隔帧仅一次）。
     * 在下一帧推进之前调用：此时无论 ENTER_FRAME 监听顺序如何，该帧模拟均已完成。
     */
    private function reportStateHash():void {
        if (onStateHash == null || _frame <= 0 || _frame == _hashedFrame || _frame % LanNetConfig.HASH_INTERVAL != 0) {
            return;
        }

        _hashedFrame = _frame;

        var runData:GameRunDataVO = GameCtrl.I.gameRunData;
        var curStg:IStage         = MainGame.stageCtrl.currentStage;
        if (!runData || !(curStg is GameStage)) {
            return;
        }

        try {
            var hash:uint = LanStateHash.compute(runData);
            onStateHash(_epoch, _frame, hash, LanStateHash.detail);
        }
        catch (e:Error) {
            trace(e);
        }
    }

    /** @private 采样本机输入并上报给中继 */
    private function sendLocalInput():void {
        _local.renderInput();

        var k:int = _local.getSocketData();
        _local.resetInput();

        _link.sendTickInput(_frame, k);
    }

    /** @private 房主：每 SYNC_GAP 帧在当前帧（尚未模拟）抓取快照发出 */
    private function sendSnapshot():void {
        if (snapshotSender == null || ++_syncCount <= LANUtils.SYNC_GAP) {
            return;
        }

        var curStg:IStage = MainGame.stageCtrl.currentStage;
        if (!(curStg is GameStage) || !GameCtrl.I.actionEnable) {
            return;
        }

        var runData:GameRunDataVO = GameCtrl.I.gameRunData;
        _syncCount                = 0;
        snapshotSender(LanInputSyncCodec.encode(
                _frame, runData.round, runData.gameTime,
                runData.p1FighterGroup.currentFighter,
                runData.p2FighterGroup.currentFighter
        ));
    }

    /** @private 客户端：把房主在本帧抓取的快照写入战斗状态 */
    private function applyPendingSnapshot():void {
        var snap:LanInputSyncSnapshot = _snaps[_frame];
        if (!snap) {
            return;
        }

        delete _snaps[_frame];
        try {
            if (GameCtrl.I.gameRunData.round != snap.round) {
                syncCore && syncCore.syncError(true);

                return;
            }

            //房主为准：-1 为无限时，客户端同步采用，避免本地限时倒计时误触发超时
            if (snap.gameTime < 0) {
                GameCtrl.I.gameRunData.gameTimeMax = -1;
            }
            else if (GameCtrl.I.gameRunData.gameTimeMax < 0) {
                GameCtrl.I.gameRunData.gameTimeMax = snap.gameTime;
            }
            GameCtrl.I.gameRunData.gameTime = snap.gameTime;
            LanInputSyncCodec.applyToFighters(
                    snap,
                    GameCtrl.I.gameRunData.p1FighterGroup.currentFighter,
                    GameCtrl.I.gameRunData.p2FighterGroup.currentFighter
            );
            syncCore && syncCore.resetSyncError();
        }
        catch (e:Error) {
            trace(e);
            syncCore && syncCore.syncError(true);
        }
    }

    /** @private 开始整场战斗段：序号递增、清空帧缓冲并通知中继 */
    private function beginSegment():void {
        if (!_link) {
            return;
        }

        _epoch++;
        _frame       = 0;
        _head        = 0;
        _pairs       = {};
        _snaps       = {};
        _started     = false;
        _syncCount   = 0;
        _finishFns    = [];
        _finishFrames = [];
        _hashedFrame = 0;
        GameCtrl.I.resetAnimatePhase();
        _active      = true;
        stallMonitor.reset();

        _link.sendTickCtrl(LanRelayTick.CMD_START, _epoch);
    }

    /** @private 结束当前战斗段（幂等）：通知中继并清零输入 */
    private function endSegment():void {
        if (!_active) {
            return;
        }

        _active       = false;
        _finishFns    = [];
        _finishFrames = [];
        _pairs       = {};
        _snaps       = {};
        stallMonitor.reset();

        if (_link) {
            _link.sendTickCtrl(LanRelayTick.CMD_STOP, _epoch);
        }
        if (_inputP1) {
            _inputP1.setSocketData(0);
            _inputP2.setSocketData(0);
        }
    }

    /** @private */
    private function removeEvents():void {
        GameEvent.removeEventListener(GameEvent.GAME_START, onGameStart);
        GameEvent.removeEventListener(GameEvent.GAME_END, onGameEnd);
    }

    /** @private 新一场对局：序号递增并开始整场战斗段（此时尚无任何动画推进） */
    private function onGameStart(e:GameEvent):void {
        endSegment();
        beginSegment();
    }

    /** @private */
    private function onGameEnd(e:GameEvent):void {
        endSegment();
    }
}
}
