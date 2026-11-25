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

package net.play5d.game.bvn.interfaces.lan {

/**
 * 中继定帧锁帧对壳层会话的依赖契约。
 *
 * <p>对局中由中继服务器按固定节拍下发逐帧输入对；壳负责把下列两类控制 / 输入帧发往中继。</p>
 *
 * @example
 * <listing version="3.0">
 * var link:ILanRelayLockLink = relaySession;
 * link.sendTickCtrl(LanRelayTick.CMD_START, 1);
 * </listing>
 */
public interface ILanRelayLockLink {
    /**
     * 发送战斗段控制帧（TICK_CTRL）。
     * @param cmd <code>LanRelayTick.CMD_START</code> 或 <code>LanRelayTick.CMD_STOP</code>。
     * @param epoch 战斗段序号（一场对局内从 1 递增）。
     * @example
     * <listing version="3.0">
     * link.sendTickCtrl(LanRelayTick.CMD_STOP, 2);
     * </listing>
     */
    function sendTickCtrl(cmd:int, epoch:uint):void;

    /**
     * 发送本机最新输入帧（TICK_INPUT）。
     * @param lastFrame 本机已模拟到的帧号。
     * @param k 本机输入打包键位。
     * @example
     * <listing version="3.0">
     * link.sendTickInput(frame, k);
     * </listing>
     */
    function sendTickInput(lastFrame:uint, k:int):void;
}
}
