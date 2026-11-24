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

package net.play5d.game.bvn.web.input {
import net.play5d.game.bvn.input.GameKeyInput;
import net.play5d.game.bvn.input.GameSocketInput;

/**
 * 浏览器壳输入集合：仅键盘与联机锁帧输入（无手柄）。
 *
 * @see net.play5d.game.bvn.input.GameKeyInput
 * @see net.play5d.game.bvn.input.GameSocketInput
 */
public class InputManager {

    /** @private */
    private static var _i:InputManager;

    /**
     * 单例。
     * @return 输入集合实例。
     */
    public static function get I():InputManager {
        _i ||= new InputManager();
        return _i;
    }

    /**
     * 菜单键盘输入。
     */
    public var key_menu:GameKeyInput = new GameKeyInput();
    /**
     * P1 键盘输入。
     */
    public var key_p1:GameKeyInput = new GameKeyInput();
    /**
     * P2 键盘输入。
     */
    public var key_p2:GameKeyInput = new GameKeyInput();
    /**
     * P1 联机锁帧输入。
     */
    public var socket_input_p1:GameSocketInput = new GameSocketInput();
    /**
     * P2 联机锁帧输入。
     */
    public var socket_input_p2:GameSocketInput = new GameSocketInput();
}
}
