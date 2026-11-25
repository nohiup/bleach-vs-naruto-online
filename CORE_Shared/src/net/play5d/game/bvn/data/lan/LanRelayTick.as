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

package net.play5d.game.bvn.data.lan {

/**
 * 中继定帧（relay-paced）线格式常量。
 *
 * <p>载荷布局见 <code>tools/relay/PROTOCOL.md</code>；整数均为大端。</p>
 *
 * @see net.play5d.game.bvn.interfaces.lan.ILanRelayLockLink
 */
public class LanRelayTick {
    /** TICK_CTRL 命令：战斗段开始 */
    public static const CMD_START:int = 1;
    /** TICK_CTRL 命令：战斗段结束 */
    public static const CMD_STOP:int  = 2;

    /** 帧类型：swf 至中继的控制帧，载荷 <code>[u8 cmd][u32 epoch]</code> */
    public static const FRAME_TYPE_CTRL:int  = 6;
    /** 帧类型：swf 至中继的输入帧，载荷 <code>[u32 lastFrame][i16 k]</code> */
    public static const FRAME_TYPE_INPUT:int = 7;
    /** 帧类型：中继至 swf 的逐帧输入对，载荷 <code>[u32 startFrame][u8 count]</code> + count × <code>[i16 p1K][i16 p2K]</code> */
    public static const FRAME_TYPE_FRAME:int = 8;
}
}
