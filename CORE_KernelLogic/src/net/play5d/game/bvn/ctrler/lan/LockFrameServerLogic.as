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

import net.play5d.game.bvn.MainGame;
import net.play5d.game.bvn.ctrler.game_ctrls.GameCtrl;
import net.play5d.game.bvn.data.lan.LanMsgType;
import net.play5d.game.bvn.data.lan.LanNetConfig;
import net.play5d.game.bvn.data.vos.GameRunDataVO;
import net.play5d.game.bvn.interfaces.lan.ILanServerLockLink;
import net.play5d.game.bvn.interfaces.lan.ILanSocketInput;
import net.play5d.game.bvn.stage.GameStage;
import net.play5d.game.bvn.ctrler.lan.LANUtils;
import net.play5d.kyo.stage.IStage;

/**
 * 锁帧算法（服务端）。
 *
 * <p>等待间隔与同步间隔使用 <code>LANUtils.LOCK_KEYFRAME</code> / <code>SYNC_GAP</code>。</p>
 *
 * <p>当 <code>LanNetConfig.hostPaced</code> 为 <code>true</code> 时改走「房主主导」：
 * 房主每帧用本机 P1 输入与客户端最近一次 P2 输入推进，并把每帧实际采用的输入对下发；
 * 仅当客户端落后超过 <code>LanNetConfig.HOST_MAX_LEAD</code> 帧时才停顿。
 * 下发包 <code>INPUT_UPDATE</code>：<code>byte type, ushort startFrame, byte count, count * (short p1K, short p2K)</code>，
 * 含最近至多 <code>PACED_WINDOW</code> 帧（冗余以抵御丢包）。</p>
 *
 * @see LockFrameClientLogic
 * @see net.play5d.game.bvn.interfaces.lan.ILanServerLockLink
 * @see net.play5d.game.bvn.interfaces.lan.ILanSocketInput
 */
public class LockFrameServerLogic implements ILanLockFrame {
    /**
     * 构造锁帧服务端逻辑。
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

    /** @private */
    private var _clientFrame:int;
    /** @private */
    private var _renderFrame:int;
    /** @private */
    private var _renderNextFrame:int;
    /** @private */
    private var _renderSyncFrame:int;
    /** @private */
    private var _clientK:int = -1;
    /** @private */
    private var _serverK:int = 0;
    /** @private */
    private var _syncUpdateArr:ByteArray;
    /** @private */
    private var _sendUpdateFrame:int;
    /** @private */
    private var _sendUpdateSyncFrame:int;
    /** @private */
    private var _updateCache:Object = {};
    /** @private 房主主导：单次下发的帧窗口（含冗余） */
    private static const PACED_WINDOW:int = 4;
    /** @private 房主主导：输入缓存保留的历史帧数 */
    private static const PACED_KEEP:int = 8;
    /** @private */
    private var _link:ILanServerLockLink;
    /** @private */
    private var _inputP1:ILanSocketInput;
    /** @private */
    private var _inputP2:ILanSocketInput;

    /**
     * 注入会话与输入通道。
     * @param link 服务端会话。
     * @param inputP1 服务端本机 P1 输入。
     * @param inputP2 客户端侧 P2 输入回放通道。
     */
    public function init(link:ILanServerLockLink, inputP1:ILanSocketInput, inputP2:ILanSocketInput):void {
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
        _renderFrame     = 0;
        _renderNextFrame = 0;
        _clientK         = -1;
        _serverK         = 0;
        _syncUpdateArr   = null;
        _sendUpdateFrame = 0;
        if (LanNetConfig.hostPaced) {
            _clientFrame     = 0;
            _renderSyncFrame = 0;
            _updateCache     = {};
        }
        stallMonitor.reset();
    }

    /**
     * 当前已推进的帧号（房主主导模式下供回合 / 结束消息携带，使客户端播放到同一帧再结算）。
     */
    public function get frame():int {
        return _renderFrame;
    }

    /**
     * 兼容 <code>ILanLockFrame</code>；服务端即房主，无需延后，直接执行。
     * @param hostFrame 未使用。
     * @param fn 无参回调。
     */
    public function runAtFrame(hostFrame:int, fn:Function):void {
        fn();
    }

    /**
     * 释放引用。
     */
    public function dispose():void {
        stallMonitor.dispose();
        _link    = null;
        _inputP1 = null;
        _inputP2 = null;
    }

    /**
     * 每帧推进；等待客户端时返回 <code>false</code>。
     * @return 是否允许本帧游戏逻辑推进。
     */
    public function render():Boolean {
        var go:Boolean = renderFrame();
        stallMonitor.update(!go);

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
        if (_clientK == -1) {
            return false;
        }

        if (_renderFrame > _clientFrame + LANUtils.LOCK_KEYFRAME) {
            if (_sendUpdateFrame == 0) {
                sendUpdate();
            }
            if (_sendUpdateSyncFrame == 0) {
                sendSyncUpdate();
            }

            if (++_sendUpdateFrame > LANUtils.LOCK_KEYFRAME) {
                _sendUpdateFrame = 0;
            }
            if (++_sendUpdateSyncFrame > LANUtils.SYNC_GAP) {
                _sendUpdateSyncFrame = 0;
            }

            return false;
        }

        _inputP1.renderInput();

        if (_renderFrame % LANUtils.LOCK_KEYFRAME == 0) {
            if (_syncUpdateArr) {
                sendSyncUpdate();
                _renderSyncFrame = 0;
                _syncUpdateArr   = null;
            }
            sendUpdate();
        }

        _renderFrame++;
        _renderSyncFrame++;
        renderUpdate();

        if (_renderSyncFrame > LANUtils.SYNC_GAP) {
            _syncUpdateArr = getSyncUpdate();
        }

        return true;
    }

    /**
     * 处理客户端输入包。
     * @param kb 载荷。
     * @return 已识别时为 <code>true</code>。
     */
    public function receiveInput(kb:ByteArray):Boolean {
        if (!kb) {
            return false;
        }

        kb.position  = 0;
        var type:int = kb.readByte();
        if (type != LanMsgType.INPUT_SEND) {
            return false;
        }

        _clientFrame = kb.readUnsignedShort();
        _clientK     = kb.readShort();

        return true;
    }

    /**
     * @private 房主主导：不等待客户端；落后过多才停顿。
     * 本帧输入对 = 本机 P1 + 客户端最近一次 P2；记录并下发的就是随后自身采用的值。
     */
    private function renderFramePaced():Boolean {
        if (_renderFrame - _clientFrame > LanNetConfig.HOST_MAX_LEAD) {
            return false;
        }

        _inputP1.renderInput();

        var k1:int = _inputP1.getSocketData();
        _inputP1.resetInput();

        _renderFrame++;
        _renderSyncFrame++;
        _updateCache[_renderFrame] = [k1, _clientK < 0 ? 0 : _clientK];
        delete _updateCache[_renderFrame - PACED_KEEP];

        // 快照先于该帧输入包下发，客户端播放到该帧时再应用
        if (_renderSyncFrame > LANUtils.SYNC_GAP) {
            var snap:ByteArray = getSyncUpdate();
            if (snap) {
                _link.sendUDP(snap);
                _renderSyncFrame = 0;
            }
        }

        sendPacedUpdate();
        renderUpdate();

        return true;
    }

    /** @private 房主主导：下发最近若干帧的输入对 */
    private function sendPacedUpdate():void {
        var start:int   = Math.max(1, _renderFrame - PACED_WINDOW + 1);
        var count:int   = _renderFrame - start + 1;
        var b:ByteArray = new ByteArray();
        b.writeByte(LanMsgType.INPUT_UPDATE);
        b.writeShort(start);
        b.writeByte(count);
        for (var f:int = start; f <= _renderFrame; f++) {
            b.writeShort(_updateCache[f][0]);
            b.writeShort(_updateCache[f][1]);
        }

        _link.sendUDP(b);
    }

    /** @private */
    private function sendUpdate():void {
        _renderNextFrame = _renderFrame + LANUtils.LOCK_KEYFRAME;

        _serverK = _inputP1.getSocketData();
        _inputP1.resetInput();

        var updateByte:ByteArray = new ByteArray();
        updateByte.writeByte(LanMsgType.INPUT_UPDATE);
        updateByte.writeShort(_renderFrame);
        updateByte.writeShort(_serverK);
        updateByte.writeShort(_clientK);

        _link.sendUDP(updateByte);
        cacheUpdate();
    }

    /** @private */
    private function sendSyncUpdate():void {
        if (!_syncUpdateArr) {
            return;
        }
        _updateCache = {};
        _link.sendUDP(_syncUpdateArr);
    }

    /** @private */
    private function getSyncUpdate():ByteArray {
        var curStg:IStage = MainGame.stageCtrl.currentStage;
        if (!(curStg is GameStage) || !GameCtrl.I.actionEnable) {
            return null;
        }

        var runData:GameRunDataVO = GameCtrl.I.gameRunData;

        return LanInputSyncCodec.encode(
                _renderFrame, runData.round, runData.gameTime,
                runData.p1FighterGroup.currentFighter,
                runData.p2FighterGroup.currentFighter
        );
    }

    /** @private */
    private function cacheUpdate():void {
        LockFrameInputCache.fill(_updateCache, _renderFrame, _renderNextFrame, _serverK, _clientK);
    }

    /** @private */
    private function renderUpdate():void {
        LockFrameInputCache.apply(_updateCache, _renderFrame, _inputP1, _inputP2);
    }
}
}
