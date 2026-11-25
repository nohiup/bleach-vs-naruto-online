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

/**
 * 同步内核所需的锁帧逻辑最小契约。
 *
 * <p>由 <code>LockFrameServerLogic</code> / <code>LockFrameClientLogic</code> / <code>LockFrameRelayLogic</code>
 * 实现，使 <code>LanServerSyncCore</code> 与 <code>LanClientSyncCore</code> 不依赖具体锁帧算法。</p>
 *
 * @see LanServerSyncCore
 * @see LanClientSyncCore
 */
public interface ILanLockFrame {
    /**
     * 设置是否参与渲染推进（中继定帧忽略该值，自行管理战斗段）。
     * @param v 是否参与。
     */
    function setEnabled(v:Boolean):void;

    /**
     * 当前已推进的帧号。
     */
    function get frame():int;

    /**
     * 重置帧与缓存。
     */
    function reset():void;

    /**
     * 本机推进到 <code>hostFrame</code> 帧之后再执行回调；已到达或不适用时立即执行。
     *
     * @param hostFrame 房主事件发生时的帧号。
     * @param fn 无参回调。
     */
    function runAtFrame(hostFrame:int, fn:Function):void;
}
}
