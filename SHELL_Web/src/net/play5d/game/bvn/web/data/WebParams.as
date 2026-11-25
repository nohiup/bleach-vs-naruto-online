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

package net.play5d.game.bvn.web.data {

/**
 * 页面通过 FlashVars 传入的联机参数。
 *
 * <p>参数名：<code>web</code>、<code>role</code>、<code>token</code>、<code>nick</code>、
 * <code>relayHost</code>、<code>relayPort</code>；另有可选 <code>mode</code>（<code>team</code> 为小队对战，
 * 其余为单人对战）、<code>inputDelay</code>（输入延迟帧数，1–6，默认 3，仅房主生效）、
 * <code>hp</code>（生命比例，0.5 / 1 / 2 / 3 / 5，默认 1，仅房主生效）与 <code>time</code>
 * （回合时间，30 / 60 / 90 / -1 无限，默认 60，仅房主生效）。未带 <code>web=1</code> 时 <code>web</code> 为 <code>false</code>，壳按离线模式运行。</p>
 *
 * @example
 * <listing version="3.0">
 * WebParams.I.read(loaderInfo.parameters);
 * trace(WebParams.I.role);
 * </listing>
 */
public class WebParams {
    /**
     * 角色：房主。
     * @default host
     */
    public static const ROLE_HOST:String = 'host';
    /**
     * 角色：客户端。
     * @default client
     */
    public static const ROLE_CLIENT:String = 'client';

    /**
     * 允许的生命比例。
     * @default 0.5, 1, 2, 3, 5
     */
    public static const HP_OPTIONS:Array = [0.5, 1, 2, 3, 5];
    /**
     * 允许的回合时间（秒），<code>-1</code> 为无限。
     * @default 30, 60, 90, -1
     */
    public static const TIME_OPTIONS:Array = [30, 60, 90, -1];
    /**
     * 默认生命比例。
     * @default 1
     */
    public static const HP_DEFAULT:Number = 1;
    /**
     * 默认回合时间（秒）。
     * @default 60
     */
    public static const TIME_DEFAULT:int = 60;

    /** @private */
    private static var _i:WebParams;

    /**
     * 单例。
     * @return 参数实例。
     */
    public static function get I():WebParams {
        _i ||= new WebParams();
        return _i;
    }

    /**
     * 是否联机模式（<code>web=1</code>）。
     * @default false
     */
    public var web:Boolean = false;
    /**
     * 角色，<code>host</code> 或 <code>client</code>。
     * @default host
     */
    public var role:String = ROLE_HOST;
    /**
     * 大厅发放的席位 token。
     * @default ''
     */
    public var token:String = '';
    /**
     * 玩家昵称。
     * @default ''
     */
    public var nick:String = '';
    /**
     * 中继主机名。
     * @default bvn-game
     */
    public var relayHost:String = 'bvn-game';
    /**
     * 中继端口。
     * @default 17511
     */
    public var relayPort:int = 17511;
    /**
     * 对战模式：<code>team</code> 或 <code>single</code>。
     * @default single
     */
    public var mode:String = 'single';
    /**
     * 输入延迟（帧），范围 1–6；房主据此设置锁帧输入延迟并随开局同步给客户端。
     * @default 3
     */
    public var inputDelay:int = 3;
    /**
     * 生命比例，取值见 <code>HP_OPTIONS</code>；房主据此设置并同步给客户端。
     * @default 1
     */
    public var hp:Number = HP_DEFAULT;
    /**
     * 回合时间（秒），取值见 <code>TIME_OPTIONS</code>，<code>-1</code> 为无限；房主据此设置并同步给客户端。
     * @default 60
     */
    public var time:int = TIME_DEFAULT;
    /**
     * 是否一开始就显示 FPS 叠层（FlashVar <code>showFps=1</code>）。
     * @default false
     */
    public var showFps:Boolean = false;

    /**
     * 校验生命比例，非法值回落默认。
     * @param value 待校验值。
     * @return 合法的生命比例。
     */
    public static function normalizeHp(value:*):Number {
        var n:Number = Number(value);

        return HP_OPTIONS.indexOf(n) >= 0 ? n : HP_DEFAULT;
    }

    /**
     * 校验回合时间，非法值回落默认。
     * @param value 待校验值。
     * @return 合法的回合时间（秒）。
     */
    public static function normalizeTime(value:*):int {
        var n:Number = Number(value);

        return TIME_OPTIONS.indexOf(n) >= 0 ? int(n) : TIME_DEFAULT;
    }

    /**
     * 校验输入延迟，非法值回落给定值。
     * @param value 待校验值。
     * @param fallback 非法时使用的值。
     * @return 合法的输入延迟（1–6）。
     */
    public static function normalizeDelay(value:*, fallback:int):int {
        var n:Number = Number(value);

        return n == int(n) && n >= 1 && n <= 6 ? int(n) : fallback;
    }

    /**
     * 读取 FlashVars。
     * @param params <code>loaderInfo.parameters</code>。
     * @example
     * <listing version="3.0">
     * WebParams.I.read(loaderInfo.parameters);
     * </listing>
     */
    public function read(params:Object):void {
        if (!params) {
            return;
        }

        web = params['web'] == '1' || params['web'] == 'true';

        if (params['role'] == ROLE_CLIENT) {
            role = ROLE_CLIENT;
        }
        if (params['token']) {
            token = String(params['token']);
        }
        if (params['nick']) {
            nick = String(params['nick']);
        }
        if (params['relayHost']) {
            relayHost = String(params['relayHost']);
        }
        if (params['relayPort']) {
            relayPort = int(params['relayPort']);
        }
        if (params['mode']) {
            mode = String(params['mode']);
        }
        if (params['inputDelay']) {
            inputDelay = Math.max(1, Math.min(6, int(params['inputDelay'])));
        }
        if (params['hp']) {
            hp = normalizeHp(params['hp']);
        }
        if (params['time']) {
            time = normalizeTime(params['time']);
        }

        showFps = params['showFps'] == '1' || params['showFps'] == 'true';
    }
}
}
