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
 * 联机锁帧网络参数（跨壳一致）。
 *
 * <p>输入延迟由主机在开局前设置，并随 <code>SYNC GAME_START</code> 下发给客户端；
 * 卡顿阈值供壳显示「等待对手」与放弃对局使用。</p>
 *
 * @see LanSyncType
 * @see LanSocketMsgFactory
 */
public class LanNetConfig {
    include '../../../../../../../include/ImportVersion.as';

    /** 输入延迟下限（帧，基准 30FPS） */
    public static const INPUT_DELAY_MIN:int     = 1;
    /** 输入延迟上限（帧，基准 30FPS） */
    public static const INPUT_DELAY_MAX:int     = 6;
    /** 输入延迟默认值（帧，基准 30FPS） */
    public static const INPUT_DELAY_DEFAULT:int = 3;

    /** 卡顿超过该毫秒数后，壳应显示「等待对手」 */
    public static const STALL_WARN_MS:int    = 500;
    /** 卡顿超过该毫秒数后，视为对手掉线并放弃对局 */
    public static const STALL_TIMEOUT_MS:int = 10000;

    /** @private */
    private static var _inputDelay:int = INPUT_DELAY_DEFAULT;

    /**
     * 输入延迟（帧，基准 30FPS）；赋值时夹取到 <code>INPUT_DELAY_MIN</code>~<code>INPUT_DELAY_MAX</code>。
     *
     * <p>主机须在开局（<code>LANUtils.updateParams()</code>）前设置；客户端由 SYNC 消息自动覆盖。</p>
     *
     * @default 3
     * @example
     * <listing version="3.0">
     * LanNetConfig.inputDelay = 4;
     * </listing>
     */
    public static function get inputDelay():int {
        return _inputDelay;
    }

    /** @private */
    public static function set inputDelay(v:int):void {
        _inputDelay = Math.max(INPUT_DELAY_MIN, Math.min(INPUT_DELAY_MAX, v));
    }
}
}
