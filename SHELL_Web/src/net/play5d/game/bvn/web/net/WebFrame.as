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
 * 中继线协议的单帧：类型 + 载荷。
 *
 * @see WebFrameCodec
 */
public class WebFrame {
    /**
     * 帧类型，取值见 <code>WebFrameCodec</code> 的类型常量。
     * @default 0
     */
    public var type:int;
    /**
     * 帧载荷；无载荷时为长度 0 的 <code>ByteArray</code>。
     * @default null
     */
    public var payload:ByteArray;
}
}
