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
import flash.utils.clearTimeout;
import flash.utils.setTimeout;

/**
 * 局域网选人阶段待处理消息队列。
 *
 * <p>对端可能比本机快：消息到达时对应场景（选人 / 加载）尚未进入，直接丢弃会让握手死锁。
 * 本队列按到达顺序缓存消息，并在场景进入或定时重试时依次交给应用函数；
 * 应用函数返回 <code>false</code> 表示场景未就绪，保留该消息并停止本轮。</p>
 *
 * @see SelectFighterServerLogic
 * @see SelectFighterClientLogic
 */
public class SelectFighterPendingQueue {
    /** 重试间隔（毫秒） */
    public static const RETRY_MS:int  = 100;
    /** 单条消息最多重试次数，超出后丢弃并 <code>trace</code> */
    public static const MAX_TRIES:int = 1200;

    /**
     * 构造队列。
     * @param apply 应用函数，签名 <code>function(msg:Array):Boolean</code>，已处理返回 <code>true</code>。
     */
    public function SelectFighterPendingQueue(apply:Function) {
        _apply = apply;
    }

    /** @private */
    private var _apply:Function;
    /** @private 元素为 <code>{msg:Array, tries:int}</code> */
    private var _list:Array = [];
    /** @private */
    private var _timer:uint;
    /** @private */
    private var _flushing:Boolean;

    /**
     * 当前缓存条数。
     * @return 条数。
     */
    public function get length():int {
        return _list.length;
    }

    /**
     * 入队并立即尝试处理。
     * @param msg 选人协议数组（<code>[KEY, type, ...]</code>）。
     */
    public function push(msg:Array):void {
        _list.push({msg: msg, tries: 0});
        flush();
    }

    /**
     * 按顺序尝试处理队首消息，遇到未就绪的消息即停止并安排重试。
     */
    public function flush():void {
        if (_flushing) {
            return;
        }

        _flushing = true;
        clearTimeout(_timer);

        while (_list.length > 0) {
            var item:Object  = _list[0];
            var done:Boolean = false;

            try {
                done = _apply(item.msg);
            }
            catch (e:Error) {
                if (item.tries == 0) {
                    trace('[SelectSync] apply error:', e);
                }
            }

            if (done) {
                _list.shift();
                continue;
            }

            item.tries++;
            if (item.tries > MAX_TRIES) {
                trace('[SelectSync] drop stale message, type =', item.msg[1]);
                _list.shift();
                continue;
            }

            _timer = setTimeout(flush, RETRY_MS);
            break;
        }

        _flushing = false;
    }

    /**
     * 丢弃队首连续的、类型在列表内的过期消息。
     * @param types <code>SelectFighterDataType</code> 类型列表。
     */
    public function dropLeading(types:Array):void {
        while (_list.length > 0 && types.indexOf(_list[0].msg[1]) != -1) {
            _list.shift();
        }
    }

    /**
     * 清空队列并停止重试。
     */
    public function clear():void {
        clearTimeout(_timer);
        _list.length = 0;
    }
}
}
