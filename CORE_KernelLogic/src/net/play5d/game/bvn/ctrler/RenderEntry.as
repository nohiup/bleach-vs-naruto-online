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

package net.play5d.game.bvn.ctrler {

/**
 * 主渲染归属条目。
 *
 * <p>独立成文件：若作为 <code>GameRender</code> 文件内类，其静态初始化时本类尚未定义，
 * <code>Vector.&lt;RenderEntry&gt;</code> 会类型转换失败。</p>
 *
 * @private
 * @see GameRender
 */
internal class RenderEntry {

    /** @private 归属对象 */
    public var owner:*;
    /** @private 该归属下按注册顺序排列的渲染函数 */
    public var funcs:Vector.<Function> = new Vector.<Function>();

    /**
     * 构造条目。
     *
     * @param owner 渲染函数归属
     */
    public function RenderEntry(owner:*) {
        this.owner = owner;
    }

}
}
