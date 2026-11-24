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

package net.play5d.game.bvn.web.utils {
import flash.external.ExternalInterface;

/**
 * 与大厅页面的 JS 桥（<code>ExternalInterface</code>），所有调用均在不可用或抛错时静默失败。
 *
 * <p>事件通过页面全局函数 <code>bvnOnEvent(name, json)</code> 上报；页面可调用已注册的
 * <code>bvnLeave()</code> 让 SWF 主动退出对局。</p>
 *
 * @example
 * <listing version="3.0">
 * WebBridge.emit('ping', {rtt: 42});
 * </listing>
 * @see flash.external.ExternalInterface
 */
public class WebBridge {
    /**
     * 页面事件回调的全局函数名。
     * @default bvnOnEvent
     */
    public static const EVENT_FUNC:String = 'bvnOnEvent';
    /**
     * SWF 向页面注册的退出回调名。
     * @default bvnLeave
     */
    public static const LEAVE_FUNC:String = 'bvnLeave';

    /**
     * 向页面上报事件。
     * @param name 事件名：<code>connected</code>、<code>peerReady</code>、<code>matchStart</code>、
     * <code>matchEnd</code>、<code>disconnected</code>、<code>ping</code>、<code>error</code>。
     * @param data 事件数据，序列化为 JSON；省略时为空对象。
     * @example
     * <listing version="3.0">
     * WebBridge.emit('error', {msg: 'timeout'});
     * </listing>
     */
    public static function emit(name:String, data:Object = null):void {
        if (!ExternalInterface.available) {
            return;
        }

        try {
            ExternalInterface.call(EVENT_FUNC, name, JSON.stringify(data || {}));
        }
        catch (e:Error) {
            trace('WebBridge.emit', name, e);
        }
    }

    /**
     * 注册页面可调用的退出回调 <code>bvnLeave</code>。
     * @param handler 无参回调。
     * @example
     * <listing version="3.0">
     * WebBridge.registerLeave(leave);
     * </listing>
     */
    public static function registerLeave(handler:Function):void {
        if (!ExternalInterface.available) {
            return;
        }

        try {
            ExternalInterface.addCallback(LEAVE_FUNC, handler);
        }
        catch (e:Error) {
            trace('WebBridge.registerLeave', e);
        }
    }

    /**
     * 向浏览器控制台输出一行日志。
     * @param msg 日志文本。
     * @example
     * <listing version="3.0">
     * WebBridge.log('init ok');
     * </listing>
     */
    public static function log(msg:String):void {
        if (!ExternalInterface.available) {
            return;
        }

        try {
            ExternalInterface.call('console.log', msg);
        }
        catch (e:Error) {
        }
    }
}
}
