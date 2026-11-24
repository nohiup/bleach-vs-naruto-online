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
import flash.utils.ByteArray;

/**
 * 中继 <code>/game</code> 二进制帧编解码，帧格式 <code>[u8 type][u16 length BE][payload]</code>。
 *
 * <p>静态 <code>encode</code> 负责打包；实例的 <code>push</code> 把 TCP 式字节流重组为完整帧，
 * 可处理一次收到多帧（粘包）或一帧被拆成多次（半包）。</p>
 *
 * @example
 * <listing version="3.0">
 * var codec:WebFrameCodec = new WebFrameCodec();
 * var frames:Array = codec.push(chunk);
 * </listing>
 * @see WebFrame
 */
public class WebFrameCodec {
    /**
     * 帧类型：客户端握手（携带 token），中继应答同值（携带角色）。
     * @default 0
     */
    public static const HELLO:int = 0;
    /**
     * 帧类型：中继对 <code>HELLO</code> 的应答，载荷为角色字符串。
     * @default 0
     */
    public static const HELLO_OK:int = 0;
    /**
     * 帧类型：会话消息（等价 TCP）。
     * @default 1
     */
    public static const SESSION:int = 1;
    /**
     * 帧类型：锁帧输入（等价 UDP）。
     * @default 2
     */
    public static const INPUT:int = 2;
    /**
     * 帧类型：心跳，中继原样回显。
     * @default 3
     */
    public static const PING:int = 3;
    /**
     * 帧类型：对端离开，随后中继关闭连接。
     * @default 4
     */
    public static const PEER_LEFT:int = 4;
    /**
     * 帧类型：双方席位均已认领。
     * @default 5
     */
    public static const PEER_READY:int = 5;
    /**
     * 单帧载荷上限（字节）。
     * @default 4096
     */
    public static const MAX_PAYLOAD:int = 4096;
    /**
     * 帧头长度（字节）。
     * @default 3
     */
    public static const HEAD_SIZE:int = 3;

    /**
     * 打包一帧。
     * @param type 帧类型。
     * @param payload 载荷；可为 <code>null</code>。
     * @return 完整帧字节；载荷超过 <code>MAX_PAYLOAD</code> 时返回 <code>null</code>。
     * @example
     * <listing version="3.0">
     * var bytes:ByteArray = WebFrameCodec.encode(WebFrameCodec.PING, body);
     * </listing>
     */
    public static function encode(type:int, payload:ByteArray = null):ByteArray {
        var len:int = payload ? payload.length : 0;
        if (len > MAX_PAYLOAD) {
            return null;
        }

        var out:ByteArray = new ByteArray();
        out.writeByte(type);
        out.writeShort(len);
        if (len > 0) {
            out.writeBytes(payload, 0, len);
        }

        return out;
    }

    /**
     * 对端声明了超出上限的长度（协议破坏）后置为 <code>true</code>，缓冲已清空。
     * @default false
     */
    public var corrupt:Boolean;
    /** @private 尚未组成完整帧的剩余字节 */
    private var _buffer:ByteArray = new ByteArray();

    /**
     * 追加收到的字节并取出所有已完整的帧。
     * @param chunk 本次收到的字节。
     * @return <code>WebFrame</code> 数组；不足一帧时为空数组。
     * @example
     * <listing version="3.0">
     * for each (var f:WebFrame in codec.push(chunk)) {
     *     trace(f.type);
     * }
     * </listing>
     */
    public function push(chunk:ByteArray):Array {
        var frames:Array = [];

        _buffer.position = _buffer.length;
        _buffer.writeBytes(chunk, 0, chunk.length);
        _buffer.position = 0;

        while (_buffer.length - _buffer.position >= HEAD_SIZE) {
            var start:int = _buffer.position;
            var type:int  = _buffer.readUnsignedByte();
            var len:int   = _buffer.readUnsignedShort();

            if (len > MAX_PAYLOAD) {
                corrupt = true;
                _buffer = new ByteArray();

                return frames;
            }

            if (_buffer.length - _buffer.position < len) {
                _buffer.position = start;
                break;
            }

            var frame:WebFrame = new WebFrame();
            frame.type         = type;
            frame.payload      = new ByteArray();
            if (len > 0) {
                _buffer.readBytes(frame.payload, 0, len);
            }
            frames.push(frame);
        }

        // 丢弃已消费的字节，仅保留半包
        var rest:ByteArray = new ByteArray();
        if (_buffer.position < _buffer.length) {
            _buffer.readBytes(rest, 0, _buffer.length - _buffer.position);
        }
        _buffer = rest;

        return frames;
    }
}
}
