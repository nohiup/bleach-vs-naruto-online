/*
 * Copyright (C) 2021-2024, 5DPLAY Game Studio
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

package net.play5d.game.bvn.ctrler {
import flash.display.Stage;
import flash.events.Event;
import flash.utils.Dictionary;

/**
 * 游戏渲染
 */
public class GameRender {

    // 是否渲染
    public static var isRender:Boolean = true;

    // 先于主渲染之前渲染
    private static var _beforeFuncs:Vector.<Function>;
    /** @private 主渲染：按首次注册顺序排列的归属条目，遍历顺序即调用顺序 */
    private static var _entries:Vector.<RenderEntry> = new Vector.<RenderEntry>();
    /** @private 归属 -> 条目，用于 O(1) 查找 */
    private static var _entryMap:Dictionary = new Dictionary();
    /** @private 主渲染是否正在遍历 */
    private static var _rendering:Boolean = false;
    /** @private 出现了已无函数的条目，需在合适时机整理 */
    private static var _dirty:Boolean = false;
    // 后于主渲染之后渲染
    private static var _afterFuncs:Vector.<Function>;

    /**
     * 初始化
     *
     * @param stage 游戏舞台
     */
    public static function initialize(stage:Stage):void {
        stage.addEventListener(Event.ENTER_FRAME, render);
    }

    /**
     * 添加一个先于主渲染之前渲染的函数
     *
     * @param func 渲染函数
     */
    public static function addBefore(func:Function):void {
        if (func == null) {
            return;
        }

        _beforeFuncs ||= new Vector.<Function>();

        var index:int = _beforeFuncs.indexOf(func);
        if (index == -1) {
            _beforeFuncs.push(func);
        }
    }

    /**
     * 移除一个先于主渲染之前渲染的函数
     *
     * @param func 渲染函数
     */
    public static function removeBefore(func:Function):void {
        if (func == null || !_beforeFuncs) {
            return;
        }

        var index:int = _beforeFuncs.indexOf(func);
        if (index != -1) {
            _beforeFuncs.splice(index, 1);
        }
    }

    /**
     * 添加一个主渲染函数
     *
     * <p>调用顺序固定为：归属首次注册的先后，同一归属内再按函数注册的先后，
     * 与 <code>Dictionary</code> 的遍历顺序无关（联机锁帧要求各端顺序一致）。
     * 遍历期间新增的归属排在末尾，本帧不会被调用；遍历期间向已有归属追加的函数同样本帧不调用。</p>
     *
     * @param func 渲染函数
     * @param owner 渲染函数归属
     */
    public static function add(func:Function, owner:* = null):void {
        owner ||= 'anyone';

        var entry:RenderEntry = _entryMap[owner];
        if (entry) {
            if (entry.funcs.indexOf(func) == -1) {
                entry.funcs.push(func);
            }
            return;
        }

        entry = new RenderEntry(owner);
        entry.funcs.push(func);
        _entryMap[owner] = entry;
        _entries.push(entry);
    }

    /**
     * 移除一个主渲染函数
     *
     * <p>遍历期间可安全调用：归属条目的位置保持不变，清空后在本帧遍历结束时才整理。</p>
     *
     * @param func 渲染函数
     * @param owner 渲染函数归属
     */
    public static function remove(func:Function, owner:* = null):void {
        owner ||= 'anyone';

        var entry:RenderEntry = _entryMap[owner];
        if (!entry) {
            return;
        }

        var index:int = entry.funcs.indexOf(func);
        if (index != -1) {
            entry.funcs.splice(index, 1);
        }

        if (entry.funcs.length == 0) {
            _dirty = true;
            if (!_rendering) {
                compact();
            }
        }
    }

    /**
     * 添加一个后于主渲染之后渲染的函数
     *
     * @param func 渲染函数
     */
    public static function addAfter(func:Function):void {
        if (func == null) {
            return;
        }

        _afterFuncs ||= new Vector.<Function>();

        var index:int = _afterFuncs.indexOf(func);
        if (index == -1) {
            _afterFuncs.push(func);
        }
    }

    /**
     * 移除一个后于主渲染之后渲染的函数
     *
     * @param func 渲染函数
     */
    public static function removeAfter(func:Function):void {
        if (func == null || !_afterFuncs) {
            return;
        }

        var index:int = _afterFuncs.indexOf(func);
        if (index != -1) {
            _afterFuncs.splice(index, 1);
        }
    }

    /** @private 清理已无函数的归属条目，保持其余条目的相对顺序 */
    private static function compact():void {
        _dirty = false;

        var kept:int = 0;
        var entry:RenderEntry;
        for (var i:int = 0; i < _entries.length; i++) {
            entry = _entries[i];
            if (entry.funcs.length == 0) {
                delete _entryMap[entry.owner];
                continue;
            }

            _entries[kept++] = entry;
        }
        _entries.length = kept;
    }

    private static function render(e:Event):void {
        if (!isRender) {
            return;
        }

        var i:int, length:int;
        var func:Function;
        if (_beforeFuncs) {
            length = _beforeFuncs.length;
            for (i = 0; i < length; i++) {
                if (i > _beforeFuncs.length - 1) {
                    break;
                }

                func = _beforeFuncs[i] as Function;
                if (func != null) {
                    func();
                }
            }
        }


        // 按注册顺序遍历归属；遍历期间条目列表只增不减，下标稳定，新增条目本帧不处理
        var funcs:Vector.<Function>;
        var j:int, count:int;
        _rendering = true;
        try {
            count = _entries.length;
            for (j = 0; j < count; j++) {
                funcs  = _entries[j].funcs;
                length = funcs.length;
                for (i = 0; i < length; i++) {
                    if (i > funcs.length - 1) {
                        break;
                    }

                    func = funcs[i] as Function;
                    if (func != null) {
                        func();
                    }
                }
            }
        }
        finally {
            _rendering = false;
            if (_dirty) {
                compact();
            }
        }

        if (_afterFuncs) {
            length = _afterFuncs.length;
            for (i = 0; i < length; i++) {
                if (i > _afterFuncs.length - 1) {
                    break;
                }

                func = _afterFuncs[i] as Function;
                if (func != null) {
                    func();
                }
            }
        }

    }

}
}
