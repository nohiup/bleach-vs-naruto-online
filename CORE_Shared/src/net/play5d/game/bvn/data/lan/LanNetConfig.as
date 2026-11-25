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

    /** 房主主导模式下，客户端落后房主超过该帧数（30FPS 下约 3 秒）时房主才停顿等待 */
    public static const HOST_MAX_LEAD:int = 90;
    /** 客户端抖动缓冲在「输入延迟」之上的附加帧数（自动取值时使用） */
    public static const CLIENT_BUFFER_EXTRA:int = 1;

    /**
     * 是否启用「房主主导」锁帧（高延迟 / 公网中继）。
     *
     * <p>为 <code>true</code> 时：房主不等待客户端，直接用客户端最近一次输入逐帧推进并下发每帧输入；
     * 客户端经抖动缓冲逐帧回放。房主与客户端必须取值一致，且须在开局前设置；
     * 为 <code>false</code>（默认）时保持原有局域网锁帧行为与线格式。</p>
     *
     * @default false
     * @example
     * <listing version="3.0">
     * LanNetConfig.hostPaced = true;
     * </listing>
     */
    public static var hostPaced:Boolean = false;

    /**
     * 是否启用「中继定帧」锁帧（对称网络代码）。
     *
     * <p>为 <code>true</code> 时对局中由中继按固定节拍下发逐帧输入对，双方壳均创建
     * <code>LockFrameRelayLogic</code>，各自经抖动缓冲每帧恰好推进 1 帧并采用同一对输入；
     * 房主仅作为回合 / 结束结算的元数据权威。须双方一致并在开局前设置；
     * 为 <code>false</code>（默认）时保持原有行为与线格式。</p>
     *
     * @default false
     */
    public static var relayPaced:Boolean = false;

    /** 中继定帧抖动缓冲默认帧数 */
    public static const RELAY_BUFFER_DEFAULT:int = 3;
    /**
     * 中继定帧开播前需缓冲的帧数（使用时至少取 1）。
     * @default 3
     */
    public static var relayBufferFrames:int = RELAY_BUFFER_DEFAULT;

    /** @private */
    private static var _inputDelay:int = INPUT_DELAY_DEFAULT;
    /** @private */
    private static var _clientBufferFrames:int = -1;

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

    /**
     * 房主主导模式下客户端开播前需缓冲的帧数（当前帧之后）。
     *
     * <p>赋负值表示自动：<code>inputDelay + CLIENT_BUFFER_EXTRA</code>（默认 3 + 1 = 4）。</p>
     *
     * @default 自动
     */
    public static function get clientBufferFrames():int {
        if (_clientBufferFrames >= 0) {
            return _clientBufferFrames;
        }

        return _inputDelay + CLIENT_BUFFER_EXTRA;
    }

    /** @private */
    public static function set clientBufferFrames(v:int):void {
        _clientBufferFrames = v < 0 ? -1 : Math.max(1, v);
    }
}
}
