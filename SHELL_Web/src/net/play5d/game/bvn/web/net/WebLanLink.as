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

package net.play5d.game.bvn.web.net {
import flash.events.Event;
import flash.events.IOErrorEvent;
import flash.events.ProgressEvent;
import flash.events.SecurityErrorEvent;
import flash.events.TimerEvent;
import flash.net.Socket;
import flash.utils.ByteArray;
import flash.utils.Timer;
import flash.utils.getTimer;

import net.play5d.game.bvn.ctrler.lan.LanClientSyncCore;
import net.play5d.game.bvn.data.lan.LanRelayTick;
import net.play5d.game.bvn.interfaces.lan.ILanClientLockLink;
import net.play5d.game.bvn.interfaces.lan.ILanRelayLockLink;
import net.play5d.game.bvn.interfaces.lan.ILanServerLockLink;

/**
 * 浏览器壳的联机链路：单条 Socket 连接中继，承载会话消息与锁帧输入。
 *
 * <p>连接建立后先发 <code>HELLO</code>（token），收到 <code>HELLO_OK</code> 得知角色并启动每秒一次的
 * <code>PING</code>；会话消息（TCP 等价）走 <code>SESSION</code> 帧，锁帧输入（UDP 等价）走
 * <code>INPUT</code> 帧。同时实现锁帧服务端与客户端所需的链路契约，供 <code>LockFrameServerLogic</code> /
 * <code>LockFrameClientLogic</code> 注入。中继节拍模式（<code>LanNetConfig.relayPaced</code>）下另实现
 * <code>ILanRelayLockLink</code>：经 <code>TICK_CTRL</code> / <code>TICK_INPUT</code> 帧上行，
 * 中继下发的 <code>TICK_FRAME</code> 交给 <code>onTickFrame</code>。</p>
 *
 * <p>回调属性均为可选；<code>onClose</code> 仅在非主动 <code>close()</code> 的断开时触发。</p>
 *
 * @example
 * <listing version="3.0">
 * var link:WebLanLink = new WebLanLink();
 * link.onHelloOk = function (role:String):void { trace(role); };
 * link.connect('bvn-game', 17511, token);
 * </listing>
 * @see WebFrameCodec
 */
public class WebLanLink implements ILanServerLockLink, ILanClientLockLink, ILanRelayLockLink {
    /**
     * 握手成功回调，签名 <code>Function(role:String):void</code>。
     * @default null
     */
    public var onHelloOk:Function;
    /**
     * 双方就绪回调，无参数。
     * @default null
     */
    public var onPeerReady:Function;
    /**
     * 对端离开回调，无参数。
     * @default null
     */
    public var onPeerLeft:Function;
    /**
     * 连接被动断开回调，无参数。
     * @default null
     */
    public var onClose:Function;
    /**
     * 收到会话消息回调，签名 <code>Function(data:Object):void</code>。
     * @default null
     */
    public var onSession:Function;
    /**
     * 收到锁帧输入回调，签名 <code>Function(bytes:ByteArray):void</code>。
     * @default null
     */
    public var onInput:Function;
    /**
     * 收到中继节拍帧回调，签名 <code>Function(payload:ByteArray):void</code>；
     * 载荷为 <code>TICK_FRAME</code> 去掉 3 字节帧头后的内容。
     * @default null
     */
    public var onTickFrame:Function;
    /**
     * 往返延迟回调，签名 <code>Function(rtt:int):void</code>，单位毫秒。
     * @default null
     */
    public var onRtt:Function;
    /**
     * 错误回调，签名 <code>Function(msg:String):void</code>。
     * @default null
     */
    public var onError:Function;
    /**
     * 客户端同步内核；<code>updateDelay</code> / <code>syncError</code> 转发给它。
     * @default null
     */
    public var syncCore:LanClientSyncCore;

    /** @private */
    private var _socket:Socket;
    /** @private */
    private var _codec:WebFrameCodec = new WebFrameCodec();
    /** @private */
    private var _pingTimer:Timer;
    /** @private */
    private var _token:String;
    /** @private */
    private var _closed:Boolean;

    /**
     * 是否已连接。
     * @return 底层 Socket 已连接时为 <code>true</code>。
     * @default false
     */
    public function get connected():Boolean {
        return _socket != null && _socket.connected && !_closed;
    }

    /**
     * 连接中继。
     * @param host 中继主机名（Ruffle 映射到 WebSocket 代理）。
     * @param port 中继端口。
     * @param token 大厅发放的席位 token。
     * @example
     * <listing version="3.0">
     * link.connect('bvn-game', 17511, 'abcdef');
     * </listing>
     */
    public function connect(host:String, port:int, token:String):void {
        _token  = token;
        _closed = false;
        _socket = new Socket();
        _socket.addEventListener(Event.CONNECT, onSocketConnect);
        _socket.addEventListener(Event.CLOSE, onSocketClose);
        _socket.addEventListener(IOErrorEvent.IO_ERROR, onSocketError);
        _socket.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onSocketError);
        _socket.addEventListener(ProgressEvent.SOCKET_DATA, onSocketData);

        try {
            _socket.connect(host, port);
        }
        catch (e:Error) {
            fireError(e.message);
            handleClose();
        }
    }

    /**
     * 主动关闭连接；不触发 <code>onClose</code>。
     * @example
     * <listing version="3.0">
     * link.close();
     * </listing>
     */
    public function close():void {
        _closed = true;
        stopPing();

        if (_socket) {
            _socket.removeEventListener(Event.CONNECT, onSocketConnect);
            _socket.removeEventListener(Event.CLOSE, onSocketClose);
            _socket.removeEventListener(IOErrorEvent.IO_ERROR, onSocketError);
            _socket.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, onSocketError);
            _socket.removeEventListener(ProgressEvent.SOCKET_DATA, onSocketData);
            try {
                _socket.close();
            }
            catch (e:Error) {
                trace(e);
            }
            _socket = null;
        }
    }

    /**
     * 发送会话消息（TCP 等价，<code>SESSION</code> 帧，载荷为 JSON 文本）。
     * @param data 可被 <code>JSON.stringify</code> 的对象或数组。
     * @example
     * <listing version="3.0">
     * link.sendSession(['SYNC', 1]);
     * </listing>
     */
    public function sendSession(data:Object):void {
        var body:ByteArray = new ByteArray();
        body.writeUTFBytes(JSON.stringify(data));
        sendFrame(WebFrameCodec.SESSION, body);
    }

    /**
     * 发送锁帧输入（UDP 等价，<code>INPUT</code> 帧）。
     * @param data 通常为 <code>ByteArray</code>；其它类型忽略。
     * @example
     * <listing version="3.0">
     * link.sendUDP(bytes);
     * </listing>
     */
    public function sendUDP(data:Object):void {
        var bytes:ByteArray = data as ByteArray;
        if (!bytes) {
            return;
        }

        sendFrame(WebFrameCodec.INPUT, bytes);
    }

    /**
     * 发送中继节拍控制（<code>TICK_CTRL</code> 帧，载荷 <code>[u8 cmd][u32 epoch]</code>）。
     * @param cmd 控制命令，见 <code>LanRelayTick.CMD_START</code> / <code>CMD_STOP</code>。
     * @param epoch 对局段序号（从 1 递增）。
     * @example
     * <listing version="3.0">
     * link.sendTickCtrl(LanRelayTick.CMD_START, 1);
     * </listing>
     */
    public function sendTickCtrl(cmd:int, epoch:uint):void {
        var body:ByteArray = new ByteArray();
        body.writeByte(cmd);
        body.writeUnsignedInt(epoch);
        sendFrame(LanRelayTick.FRAME_TYPE_CTRL, body);
    }

    /**
     * 发送中继节拍输入（<code>TICK_INPUT</code> 帧，载荷 <code>[u32 lastFrame][i16 k]</code>）。
     * @param lastFrame 本机已模拟的最新帧号。
     * @param k 本机最新输入位掩码。
     * @example
     * <listing version="3.0">
     * link.sendTickInput(frame, keys);
     * </listing>
     */
    public function sendTickInput(lastFrame:uint, k:int):void {
        var body:ByteArray = new ByteArray();
        body.writeUnsignedInt(lastFrame);
        body.writeShort(k);
        sendFrame(LanRelayTick.FRAME_TYPE_INPUT, body);
    }

    /**
     * 更新显示用延迟，转发给 <code>syncCore</code>。
     * @param v 毫秒。
     */
    public function updateDelay(v:int):void {
        if (syncCore) {
            syncCore.updateDelay(v);
        }
    }

    /**
     * 报告同步错误，转发给 <code>syncCore</code>。
     * @param wait 是否进入等待态。
     */
    public function syncError(wait:Boolean = false):void {
        if (syncCore) {
            syncCore.syncError(wait);
        }
    }

    /**
     * 清除同步错误标记，转发给 <code>syncCore</code>。
     */
    public function resetSyncError():void {
        if (syncCore) {
            syncCore.resetSyncError();
        }
    }

    /** @private */
    private function sendFrame(type:int, payload:ByteArray = null):void {
        if (!connected) {
            return;
        }

        var bytes:ByteArray = WebFrameCodec.encode(type, payload);
        if (!bytes) {
            trace('WebLanLink: payload too large, type =', type);

            return;
        }

        try {
            _socket.writeBytes(bytes, 0, bytes.length);
            _socket.flush();
        }
        catch (e:Error) {
            trace('WebLanLink.sendFrame', e);
        }
    }

    /** @private */
    private function startPing():void {
        if (_pingTimer) {
            return;
        }

        _pingTimer = new Timer(1000);
        _pingTimer.addEventListener(TimerEvent.TIMER, onPingTimer);
        _pingTimer.start();
    }

    /** @private */
    private function stopPing():void {
        if (_pingTimer) {
            _pingTimer.stop();
            _pingTimer.removeEventListener(TimerEvent.TIMER, onPingTimer);
            _pingTimer = null;
        }
    }

    /** @private */
    private function onPingTimer(e:TimerEvent):void {
        var body:ByteArray = new ByteArray();
        body.writeDouble(getTimer());
        sendFrame(WebFrameCodec.PING, body);
    }

    /** @private */
    private function onSocketConnect(e:Event):void {
        var body:ByteArray = new ByteArray();
        body.writeUTFBytes(_token);
        sendFrame(WebFrameCodec.HELLO, body);
    }

    /** @private */
    private function onSocketClose(e:Event):void {
        handleClose();
    }

    /** @private */
    private function onSocketError(e:Event):void {
        fireError(e.toString());
        handleClose();
    }

    /** @private */
    private function onSocketData(e:ProgressEvent):void {
        if (_closed || !_socket) {
            return;
        }

        var chunk:ByteArray = new ByteArray();
        _socket.readBytes(chunk, 0, _socket.bytesAvailable);

        var frames:Array = _codec.push(chunk);
        for each (var frame:WebFrame in frames) {
            if (_closed) {
                return;
            }
            dispatchFrame(frame);
        }

        if (_codec.corrupt) {
            fireError('bad frame length');
            handleClose();
        }
    }

    /** @private */
    private function dispatchFrame(frame:WebFrame):void {
        var payload:ByteArray = frame.payload;
        payload.position      = 0;

        switch (frame.type) {
        case WebFrameCodec.HELLO_OK:
            startPing();
            if (onHelloOk != null) {
                onHelloOk(payload.readUTFBytes(payload.length));
            }
            break;
        case WebFrameCodec.SESSION:
            dispatchSession(payload);
            break;
        case WebFrameCodec.INPUT:
            if (onInput != null) {
                onInput(payload);
            }
            break;
        case LanRelayTick.FRAME_TYPE_FRAME:
            if (onTickFrame != null) {
                onTickFrame(payload);
            }
            break;
        case WebFrameCodec.PING:
            if (onRtt != null && payload.length >= 8) {
                onRtt(int(getTimer() - payload.readDouble()));
            }
            break;
        case WebFrameCodec.PEER_LEFT:
            if (onPeerLeft != null) {
                onPeerLeft();
            }
            break;
        case WebFrameCodec.PEER_READY:
            if (onPeerReady != null) {
                onPeerReady();
            }
            break;
        }
    }

    /** @private */
    private function dispatchSession(payload:ByteArray):void {
        if (onSession == null) {
            return;
        }

        var data:Object;
        try {
            data = JSON.parse(payload.readUTFBytes(payload.length));
        }
        catch (e:Error) {
            trace('WebLanLink: bad session payload', e);

            return;
        }

        onSession(data);
    }

    /** @private */
    private function fireError(msg:String):void {
        if (onError != null) {
            onError(msg);
        }
    }

    /** @private 被动断开：释放资源后通知上层，仅触发一次 */
    private function handleClose():void {
        if (_closed) {
            return;
        }

        close();

        if (onClose != null) {
            onClose();
        }
    }
}
}
