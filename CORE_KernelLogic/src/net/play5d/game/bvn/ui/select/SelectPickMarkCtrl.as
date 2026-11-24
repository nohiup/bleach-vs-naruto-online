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

package net.play5d.game.bvn.ui.select {
import flash.display.Sprite;
import flash.events.Event;
import flash.filters.GlowFilter;
import flash.text.TextFormatAlign;
import flash.utils.getTimer;

import net.play5d.game.bvn.GameConfig;
import net.play5d.game.bvn.ui.UIUtils;
import net.play5d.kyo.display.BitmapText;

/**
 * 选人「已确认」标记：在已选头像上绘制脉动发光边框与 READY 标签，并可在本机一侧显示「等待对手」提示。
 *
 * <p>全部用代码绘制（<code>Sprite</code> / <code>Graphics</code> / <code>GlowFilter</code>），不依赖 FLA 素材，
 * Ruffle 与 AIR 均可用。标记按玩家独立维护：同一玩家再次 <code>mark</code> 会重建其全部标记（小队模式逐个追加）；
 * 步骤切换（角色 → 援助 → 地图）或离开场景时由场景调用 <code>clear</code> / <code>destroy</code>。</p>
 *
 * @see SelectFighterListCtrl#findItemsByIds()
 */
public class SelectPickMarkCtrl {

    /** P1 标记色（暖红，与 P1 侧选人光标同色系） */
    public static const COLOR_P1:uint = 0xff5a3c;
    /** P2 标记色（冷蓝，与 P2 侧选人光标同色系） */
    public static const COLOR_P2:uint = 0x3c9bff;

    /** @private 头像边长 */
    private static const FACE_SIZE:int   = 50;
    /** @private 边框外扩 */
    private static const FRAME_PAD:int   = 3;
    /** @private 标签高度 */
    private static const BADGE_H:int     = 15;
    /** @private 标签宽度 */
    private static const BADGE_W:int     = 56;
    /** @private 等待提示宽度（与底部已选栏同宽） */
    private static const WAIT_W:int      = 255;
    /** @private 脉动周期系数（毫秒） */
    private static const PULSE_MS:Number = 160;

    /**
     * @param markParent 标记所在容器（头像列表容器，随列表同坐标系）。
     * @param hintParent 「等待对手」提示所在容器（场景根）。
     */
    public function SelectPickMarkCtrl(markParent:Sprite, hintParent:Sprite) {
        _markParent = markParent;
        _hintParent = hintParent;

        _layer = new Sprite();
        _layer.mouseEnabled = _layer.mouseChildren = false;
        _layer.addEventListener(Event.ENTER_FRAME, pulse);
        _markParent.addChild(_layer);
    }

    /** @private */
    private var _markParent:Sprite;
    /** @private */
    private var _hintParent:Sprite;
    /** @private 标记层 */
    private var _layer:Sprite;
    /** @private 玩家（1 / 2）→ 该玩家的标记 <code>Sprite</code> 数组 */
    private var _marks:Object = {};
    /** @private 玩家（1 / 2）→ 等待提示 */
    private var _waits:Object = {};

    /**
     * 重建某玩家的全部已选标记。
     *
     * @param player 玩家编号（1 / 2）。
     * @param items 已选头像格子（<code>SelectFighterItem</code> 数组，按确认顺序）。
     * @param finished 该玩家本步是否已全部选完；选完时在最后一个头像上方显示 READY 标签。
     */
    public function mark(player:int, items:Array, finished:Boolean):void {
        removeMarks(player);

        var color:uint   = player == 1 ? COLOR_P1 : COLOR_P2;
        var list:Array   = [];
        var count:int    = items.length;

        for (var i:int = 0; i < count; i++) {
            var item:SelectFighterItem = items[i];
            if (!item || !item.ui) {
                continue;
            }
            list.push(createMark(item, color, finished && i == count - 1));
        }

        _marks[player] = list;

        _markParent.addChild(_layer);
    }

    /**
     * 显示 / 隐藏某玩家一侧的「等待对手」提示。
     *
     * @param player 玩家编号（1 / 2），提示靠该玩家的底部已选栏一侧。
     * @param v 是否显示。
     */
    public function showWaiting(player:int, v:Boolean):void {
        var txt:BitmapText = _waits[player];

        if (!v) {
            if (txt) {
                txt.visible = false;
            }
            return;
        }

        if (!txt) {
            txt = new BitmapText(true, 0xffffff, [new GlowFilter(0, 1, 3, 3, 3)]);
            UIUtils.formatText(
                    txt.textfield,
                    {color: 0xffffff, size: 14, align: player == 1 ? TextFormatAlign.LEFT : TextFormatAlign.RIGHT}
            );
            txt.width = WAIT_W;
            txt.text  = GetLang('txt.select_fighter_stage.waiting_opponent');
            txt.x     = player == 1 ? 10 : GameConfig.GAME_SIZE.x - 10 - WAIT_W;
            txt.y     = GameConfig.GAME_SIZE.y - 104;

            _hintParent.addChild(txt);
            _waits[player] = txt;
        }

        txt.visible = true;
    }

    /**
     * 清除全部标记与等待提示（步骤切换时调用）。
     */
    public function clear():void {
        removeMarks(1);
        removeMarks(2);
        showWaiting(1, false);
        showWaiting(2, false);
    }

    /**
     * 释放全部资源（离开场景时调用）。
     */
    public function destroy():void {
        clear();

        for (var key:String in _waits) {
            var txt:BitmapText = _waits[key];
            if (txt) {
                txt.parent && txt.parent.removeChild(txt);
                txt.destroy();
            }
        }
        _waits = {};

        if (_layer) {
            _layer.removeEventListener(Event.ENTER_FRAME, pulse);
            _layer.parent && _layer.parent.removeChild(_layer);
            _layer = null;
        }

        _markParent = null;
        _hintParent = null;
    }

    /**
     * @private
     * 绘制单个头像的标记：半透明底色 + 粗圆角边框 + 发光；需要时附带 READY 标签。
     */
    private function createMark(item:SelectFighterItem, color:uint, withBadge:Boolean):Sprite {
        var s:Sprite = new Sprite();
        s.mouseEnabled = s.mouseChildren = false;
        s.x = item.ui.x;
        s.y = item.ui.y;

        var size:int = FACE_SIZE + FRAME_PAD * 2;

        s.graphics.lineStyle(3, color, 1);
        s.graphics.beginFill(color, 0.2);
        s.graphics.drawRoundRect(-FRAME_PAD, -FRAME_PAD, size, size, 8, 8);
        s.graphics.endFill();

        if (withBadge) {
            var badgeY:Number = item.ui.y < BADGE_H + 6 ? size - FRAME_PAD + 2 : -FRAME_PAD - BADGE_H - 1;
            var badgeX:Number = (FACE_SIZE - BADGE_W) / 2;

            s.graphics.lineStyle(0, 0, 0);
            s.graphics.beginFill(color, 1);
            s.graphics.drawRoundRect(badgeX, badgeY, BADGE_W, BADGE_H, 6, 6);
            s.graphics.endFill();

            var label:BitmapText = new BitmapText(true, 0xffffff, [new GlowFilter(0, 1, 2, 2, 3)]);
            UIUtils.formatText(label.textfield, {color: 0xffffff, size: 12, align: TextFormatAlign.CENTER});
            label.width = BADGE_W;
            label.text  = GetLang('txt.select_fighter_stage.picked');
            label.x     = badgeX;
            label.y     = badgeY - 1;
            s.addChild(label);
        }

        s.filters = [new GlowFilter(color, 0.9, 12, 12, 2, 2)];

        _layer.addChild(s);

        return s;
    }

    /** @private */
    private function removeMarks(player:int):void {
        var list:Array = _marks[player];
        if (!list) {
            return;
        }

        for each(var s:Sprite in list) {
            s.parent && s.parent.removeChild(s);
        }
        delete _marks[player];
    }

    /** @private 每帧脉动：标记与等待提示的透明度随时间呼吸 */
    private function pulse(e:Event):void {
        var a:Number = 0.78 + 0.22 * Math.sin(getTimer() / PULSE_MS);
        _layer.alpha = a;

        for each(var txt:BitmapText in _waits) {
            if (txt && txt.visible) {
                txt.alpha = 0.6 + 0.4 * Math.sin(getTimer() / (PULSE_MS * 2));
            }
        }
    }

}
}
