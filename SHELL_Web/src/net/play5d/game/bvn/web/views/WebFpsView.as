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
package net.play5d.game.bvn.web.views {
import flash.display.Sprite;
import flash.display.Stage;
import flash.events.Event;
import flash.text.TextField;
import flash.text.TextFieldAutoSize;
import flash.text.TextFormat;
import flash.utils.getTimer;

import net.play5d.game.bvn.GameConfig;

/**
 * FPS 叠层：舞台右上角的半透明小框，约每 0.5 秒刷新一次渲染帧率（<code>ENTER_FRAME</code> 计数）、
 * 舞台帧率与逻辑帧率（<code>GameConfig.FPS_GAME</code>）。仅一个 <code>TextField</code>，无滤镜；隐藏时不监听帧事件。
 *
 * @example
 * <listing version="3.0">
 * var fps:WebFpsView = new WebFpsView(stage);
 * fps.toggle(true);
 * </listing>
 * @see net.play5d.game.bvn.GameConfig
 */
public class WebFpsView extends Sprite {
    /** @private 刷新间隔（毫秒） */
    private static const UPDATE_MS:int = 500;

    /**
     * 构造叠层（默认隐藏）。
     * @param stage 舞台，显示时叠层加到其最上层。
     */
    public function WebFpsView(stage:Stage) {
        _stage = stage;

        _txt                   = new TextField();
        _txt.defaultTextFormat = new TextFormat('_sans', 12, 0x00ff66);
        _txt.selectable        = false;
        _txt.mouseEnabled      = false;
        _txt.autoSize          = TextFieldAutoSize.LEFT;
        _txt.text              = 'FPS --';
        _txt.x                 = 4;
        _txt.y                 = 2;
        addChild(_txt);

        mouseEnabled  = false;
        mouseChildren = false;
    }

    /** @private */
    private var _stage:Stage;
    /** @private */
    private var _txt:TextField;
    /** @private 是否显示中 */
    private var _shown:Boolean;
    /** @private 统计窗口起点（<code>getTimer</code> 毫秒） */
    private var _t0:int;
    /** @private 统计窗口内帧数 */
    private var _frames:int;

    /**
     * 显示或隐藏叠层；显示时加到舞台最上层并开始统计，隐藏时移除并停止监听。
     * @param show 为 <code>null</code> 时取反，否则按布尔值设置。
     */
    public function toggle(show:* = null):void {
        var v:Boolean = show == null ? !_shown : Boolean(show);
        if (v == _shown) {
            return;
        }

        _shown = v;

        if (v) {
            _stage.addChild(this);
            reposition();
            _frames = 0;
            _t0     = getTimer();
            addEventListener(Event.ENTER_FRAME, onFrame);
        }
        else {
            removeEventListener(Event.ENTER_FRAME, onFrame);
            if (parent) {
                parent.removeChild(this);
            }
        }
    }

    /** @private */
    private function reposition():void {
        graphics.clear();
        graphics.beginFill(0x000000, 0.55);
        graphics.drawRect(0, 0, _txt.width + 8, _txt.height + 4);
        graphics.endFill();
        x = GameConfig.GAME_SIZE.x - width - 4;
        y = 4;
    }

    /** @private */
    private function onFrame(e:Event):void {
        _frames++;

        var now:int = getTimer();
        var dt:int  = now - _t0;
        if (dt < UPDATE_MS) {
            return;
        }

        _txt.text = 'FPS ' + (_frames * 1000 / dt).toFixed(1)
                + ' | stage ' + int(_stage.frameRate)
                + ' | logic ' + GameConfig.FPS_GAME;
        reposition();
        _frames = 0;
        _t0     = now;
    }
}
}
