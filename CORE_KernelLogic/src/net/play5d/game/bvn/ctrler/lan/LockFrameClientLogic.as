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
import flash.utils.getTimer;

import net.play5d.game.bvn.ctrler.game_ctrls.GameCtrl;
import net.play5d.game.bvn.data.lan.LanMsgType;
import net.play5d.game.bvn.data.lan.LanNetConfig;
import net.play5d.game.bvn.interfaces.lan.ILanClientLockLink;
import net.play5d.game.bvn.interfaces.lan.ILanSocketInput;
import net.play5d.game.bvn.ctrler.lan.LANUtils;

/**
 * 锁帧算法（客户端）。
 *
 * <p>通过 <code>init</code> 注入会话与双方 <code>ILanSocketInput</code>。</p>
 *
 * <p>当 <code>LanNetConfig.hostPaced</code> 为 <code>true</code> 时改走「房主主导」：
 * 客户端把房主下发的逐帧输入对放入抖动缓冲，缓冲满 <code>LanNetConfig.clientBufferFrames</code>
 * 帧后每次 <code>render</code> 严格推进 1 帧（逻辑不可在同一 ENTER_FRAME 内重复步进，
 * 否则 MovieClip 时间轴与逻辑失步，故不做追帧）；缓冲耗尽则停顿并重新缓冲。
 * 每次 <code>render</code> 都上报本机输入与当前帧号。房主下发的快照与回合 / 结束消息
 * 均延后到本机播放至房主同一帧时再应用。</p>
 *
 * @see LockFrameServerLogic
 * @see net.play5d.game.bvn.interfaces.lan.ILanClientLockLink
 * @see net.play5d.game.bvn.interfaces.lan.ILanSocketInput
 */
public class LockFrameClientLogic implements ILanLockFrame {
    /**
     * 构造锁帧客户端逻辑。
     */

    /**
     * 是否参与渲染推进。
     * @default true
     */
    public var enabled:Boolean = true;

    /**
     * 卡顿监视；壳可设置其 <code>onStall</code> / <code>onResume</code> / <code>onTimeout</code>。
     */
    public var stallMonitor:LanStallMonitor = new LanStallMonitor();

    /**
     * 卡顿超过 <code>LanNetConfig.STALL_TIMEOUT_MS</code> 时是否经 <code>ILanClientLockLink.syncError(false)</code> 触发致命错误；壳自行处理 <code>onTimeout</code> 时可置 <code>false</code>。
     * @default true
     */
    public var fatalOnStallTimeout:Boolean = true;

    /** @private */
    private var _updateCache:Object = {};
    /** @private */
    private var _clientK:int;
    /** @private */
    private var _serverK:int;
    /** @private */
    private var _clientFrame:int;
    /** @private */
    private var _serverFrame:int;
    /** @private */
    private var _serverNextFrame:int;
    /** @private */
    private var _lastSendK:int;
    /** @private */
    private var _delayTimer:int = 0;
    /** @private */
    private var _sendAnyWay:Boolean = false;
    /** @private 准备包发送节流计数 */
    private var _sendStartFrame:int = 0;
    /** @private 房主主导：缓冲中已连续收到的最大房主帧号 */
    private var _pacedHead:int;
    /** @private 房主主导：是否已满足开播缓冲 */
    private var _pacedStarted:Boolean;
    /** @private 房主主导：待到帧应用的状态快照（帧号 -> 快照） */
    private var _pacedSnaps:Object = {};
    /** @private 房主主导：待到帧执行的结算回调及其目标帧 */
    private var _finishFn:Function;
    /** @private */
    private var _finishFrame:int = -1;
    /** @private */
    private static const PACED_KEEP:int = 8;
    /** @private */
    private var _link:ILanClientLockLink;
    /** @private 本机视角下的 P1（服务端侧）输入 */
    private var _inputP1:ILanSocketInput;
    /** @private 本机采集的 P2 输入 */
    private var _inputP2:ILanSocketInput;

    /**
     * 注入会话与输入通道。
     * @param link 客户端会话。
     * @param inputP1 P1 Socket 输入。
     * @param inputP2 P2 Socket 输入。
     */
    public function init(link:ILanClientLockLink, inputP1:ILanSocketInput, inputP2:ILanSocketInput):void {
        _link    = link;
        _inputP1 = inputP1;
        _inputP2 = inputP2;
    }

    /**
     * 兼容 <code>ILanLockFrame</code>：设置 <code>enabled</code>。
     * @param v 是否参与渲染推进。
     */
    public function setEnabled(v:Boolean):void {
        enabled = v;
    }

    /**
     * 重置帧与缓存。
     */
    public function reset():void {
        _updateCache     = {};
        _clientK         = 0;
        _serverK         = 0;
        _clientFrame     = 0;
        _serverFrame     = 0;
        _serverNextFrame = 0;
        _lastSendK       = 0;
        _sendStartFrame  = 0;
        _pacedHead       = 0;
        _pacedStarted    = false;
        _pacedSnaps      = {};
        _finishFn        = null;
        _finishFrame     = -1;
        stallMonitor.reset();
    }

    /**
     * 本机已播放到的帧号。
     */
    public function get frame():int {
        return _clientFrame;
    }

    /**
     * 房主主导模式下抖动缓冲中尚未播放的帧数（可供壳显示）。
     */
    public function get bufferedFrames():int {
        return _pacedHead - _clientFrame;
    }

    /**
     * 本机播放到房主帧 <code>hostFrame</code> 之后再执行回调；已到达或不适用时立即执行。
     *
     * @param hostFrame 房主事件发生时的帧号。
     * @param fn 无参回调。
     */
    public function runAtFrame(hostFrame:int, fn:Function):void {
        if (!enabled || _clientFrame >= hostFrame) {
            fn();

            return;
        }

        _finishFrame = hostFrame;
        _finishFn    = fn;
    }

    /**
     * 释放缓存引用。
     */
    public function dispose():void {
        stallMonitor.dispose();
        _updateCache = {};
        _pacedSnaps  = {};
        _finishFn    = null;
        _link        = null;
        _inputP1     = null;
        _inputP2     = null;
    }

    /**
     * 处理服务端输入更新包。
     * @param msgArr 载荷。
     * @return 已识别时为 <code>true</code>。
     */
    public function receiveUpdate(msgArr:ByteArray):Boolean {
        if (!msgArr) {
            return false;
        }

        msgArr.position = 0;
        var type:int    = msgArr.readByte();
        if (type != LanMsgType.INPUT_UPDATE) {
            return false;
        }
        if (LanNetConfig.hostPaced) {
            return receivePacedUpdate(msgArr);
        }

        _serverFrame = msgArr.readShort();
        _serverK     = msgArr.readShort();
        _clientK     = msgArr.readShort();

        _serverNextFrame = _serverFrame + LANUtils.LOCK_KEYFRAME;
        cacheUpdate();

        var delay:int = getTimer() - _delayTimer;
        _link.updateDelay(delay);
        _delayTimer = getTimer();
        _sendAnyWay = true;

        return true;
    }

    /**
     * 处理服务端状态同步包。
     * @param msgArr 载荷。
     * @return 已识别时为 <code>true</code>。
     */
    public function receiveSyncUpdate(msgArr:ByteArray):Boolean {
        var snap:LanInputSyncSnapshot = LanInputSyncCodec.decode(msgArr);
        if (!snap) {
            return false;
        }

        if (LanNetConfig.hostPaced) {
            _pacedSnaps[snap.frame] = snap;

            return true;
        }

        _updateCache = {};
        _serverFrame = snap.frame;
        applySnapshot(snap);

        return true;
    }

    /** @private 将房主状态快照写入本机战斗状态 */
    private function applySnapshot(snap:LanInputSyncSnapshot):void {
        try {
            if (GameCtrl.I.gameRunData.round != snap.round) {
                _link.syncError(true);

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
            _link.resetSyncError();
        }
        catch (e:Error) {
            trace(e);
            _link.syncError(true);
        }
    }

    /**
     * 每帧推进；未就绪时返回 <code>false</code> 以停顿渲染。
     * @return 是否允许本帧游戏逻辑推进。
     */
    public function render():Boolean {
        var go:Boolean = renderFrame();
        stallMonitor.update(!go);
        if (fatalOnStallTimeout && _link && stallMonitor.stallMs >= LanNetConfig.STALL_TIMEOUT_MS) {
            stallMonitor.reset();
            trace('LockFrameClientLogic: stall timeout, give up');
            _link.syncError(false);
        }

        return go;
    }

    /** @private */
    private function renderFrame():Boolean {
        if (!enabled) {
            return true;
        }
        if (LanNetConfig.hostPaced) {
            return renderFramePaced();
        }

        if (_serverNextFrame == 0 && _serverFrame == 0) {
            if (_sendStartFrame++ == 0) {
                var byte:ByteArray = new ByteArray();
                byte.writeByte(LanMsgType.INPUT_SEND);
                byte.writeShort(0);
                byte.writeShort(0);
                _link.sendUDP(byte);
            }
            else if (_sendStartFrame > 5) {
                _sendStartFrame = 0;
            }

            return false;
        }

        if (_clientFrame < _serverNextFrame) {
            _clientFrame++;
            renderUpdate();
            _inputP2.renderInput();

            if (_clientFrame % 2 == 0) {
                sendCtrl();
            }

            return true;
        }

        return false;
    }

    /** @private 房主主导：解析逐帧输入对并推进连续缓冲头 */
    private function receivePacedUpdate(msgArr:ByteArray):Boolean {
        var start:int = msgArr.readUnsignedShort();
        var count:int = msgArr.readUnsignedByte();
        var k1:int;
        var k2:int;
        for (var i:int = 0; i < count; i++) {
            k1 = msgArr.readShort();
            k2 = msgArr.readShort();
            if (start + i > _clientFrame) {
                _updateCache[start + i] = [k1, k2];
            }
        }

        while (_updateCache[_pacedHead + 1]) {
            _pacedHead++;
        }

        _link.updateDelay(getTimer() - _delayTimer);
        _delayTimer = getTimer();

        return true;
    }

    /** @private 房主主导：上报输入、按抖动缓冲每次推进 1 帧 */
    private function renderFramePaced():Boolean {
        sendPacedInput();

        if (_finishFn != null && _clientFrame >= _finishFrame) {
            var fn:Function = _finishFn;
            _finishFn       = null;
            _finishFrame    = -1;
            fn();

            return false;
        }

        var buffered:int = _pacedHead - _clientFrame;
        if (!_pacedStarted) {
            // 房主已结束时不会再有新帧，余量播完即可
            if (buffered < (_finishFn != null ? 1 : LanNetConfig.clientBufferFrames)) {
                return false;
            }
            _pacedStarted = true;
        }
        if (buffered < 1) {
            _pacedStarted = false;

            return false;
        }

        _clientFrame++;

        var snap:LanInputSyncSnapshot = _pacedSnaps[_clientFrame];
        if (snap) {
            delete _pacedSnaps[_clientFrame];
            applySnapshot(snap);
        }

        renderUpdate();
        delete _updateCache[_clientFrame - PACED_KEEP];

        return true;
    }

    /** @private 房主主导：每次 render 无条件上报本机输入与当前帧号 */
    private function sendPacedInput():void {
        _inputP2.renderInput();

        var k:int = _inputP2.getSocketData();
        _inputP2.resetInput();

        var byte:ByteArray = new ByteArray();
        byte.writeByte(LanMsgType.INPUT_SEND);
        byte.writeShort(_clientFrame);
        byte.writeShort(k);
        _link.sendUDP(byte);
    }

    /** @private */
    private function sendCtrl():void {
        var k:int = _inputP2.getSocketData();
        if (_lastSendK == k && !_sendAnyWay) {
            return;
        }

        _sendAnyWay = false;
        _inputP2.resetInput();

        var byte:ByteArray = new ByteArray();
        byte.writeByte(LanMsgType.INPUT_SEND);
        byte.writeShort(_clientFrame);
        byte.writeShort(k);
        _link.sendUDP(byte);

        _lastSendK = k;
    }

    /** @private */
    private function cacheUpdate():void {
        LockFrameInputCache.fill(_updateCache, _serverFrame, _serverNextFrame, _serverK, _clientK);
    }

    /** @private */
    private function renderUpdate():void {
        LockFrameInputCache.apply(_updateCache, _clientFrame, _inputP1, _inputP2);
    }
}
}
