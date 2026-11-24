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
import flash.utils.getTimer;

import net.play5d.game.bvn.data.lan.LanNetConfig;

/**
 * 锁帧卡顿监视：统计等待对手输入的连续时长并回调壳层。
 *
 * <p>由 <code>LockFrameServerLogic</code> / <code>LockFrameClientLogic</code> 每帧喂入是否卡顿；
 * 超过 <code>LanNetConfig.STALL_WARN_MS</code> 后每帧回调 <code>onStall</code>，
 * 超过 <code>LanNetConfig.STALL_TIMEOUT_MS</code> 时回调一次 <code>onTimeout</code>。</p>
 *
 * @see LanNetConfig
 * @example
 * <listing version="3.0">
 * logic.stallMonitor.onStall   = function (ms:int):void { showWaiting(ms); };
 * logic.stallMonitor.onResume  = function (ms:int):void { hideWaiting(); };
 * logic.stallMonitor.onTimeout = function (ms:int):void { giveUp(); };
 * </listing>
 */
public class LanStallMonitor {

    /**
     * 卡顿持续超过预警阈值期间每帧回调，签名 <code>Function(stallMs:int):void</code>。
     */
    public var onStall:Function;
    /**
     * 曾触发预警的卡顿结束时回调一次，签名 <code>Function(stallMs:int):void</code>。
     */
    public var onResume:Function;
    /**
     * 卡顿超过放弃阈值时回调一次，签名 <code>Function(stallMs:int):void</code>。
     */
    public var onTimeout:Function;

    /** @private 卡顿起点（<code>getTimer</code> 毫秒），未卡顿为 -1 */
    private var _startTime:int = -1;
    /** @private */
    private var _warned:Boolean;
    /** @private */
    private var _timeoutFired:Boolean;

    /**
     * 当前连续卡顿毫秒数；未卡顿为 0。
     */
    public function get stallMs():int {
        return _startTime < 0 ? 0 : getTimer() - _startTime;
    }

    /**
     * 是否处于卡顿中。
     */
    public function get stalled():Boolean {
        return _startTime >= 0;
    }

    /**
     * 每帧调用，传入本帧是否因等待对手而无法推进。
     * @param stalled 本帧是否卡顿。
     */
    public function update(stalled:Boolean):void {
        if (!stalled) {
            if (_startTime >= 0) {
                var ms:int = getTimer() - _startTime;
                reset();
                if (_warned && onResume != null) {
                    onResume(ms);
                }
            }
            return;
        }

        if (_startTime < 0) {
            _startTime = getTimer();
        }

        var cur:int = getTimer() - _startTime;
        if (cur >= LanNetConfig.STALL_WARN_MS) {
            _warned = true;
            if (onStall != null) {
                onStall(cur);
            }
        }
        if (cur >= LanNetConfig.STALL_TIMEOUT_MS && !_timeoutFired) {
            _timeoutFired = true;
            if (onTimeout != null) {
                onTimeout(cur);
            }
        }
    }

    /**
     * 清空卡顿状态（不触发回调）。
     */
    public function reset():void {
        _startTime    = -1;
        _warned       = false;
        _timeoutFired = false;
    }

    /**
     * 清空状态并释放回调引用。
     */
    public function dispose():void {
        reset();
        onStall   = null;
        onResume  = null;
        onTimeout = null;
    }
}
}
