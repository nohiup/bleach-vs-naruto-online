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
import net.play5d.game.bvn.web.ctrls.WebSessionCtrl;

/**
 * FPS 叠层：舞台右上角的半透明小框，约每 0.5 秒刷新一次实际游戏帧率
 * （锁帧渲染回调返回 <code>true</code>、逻辑真正推进的帧数每秒；无会话时等同渲染帧率）、渲染帧率（<code>ENTER_FRAME</code> 计数）、
 * 近 1 秒锁帧卡顿占比（渲染回调返回 <code>false</code> 的帧数比例）与舞台帧率；第二行为抖动缓冲帧数 <code>buf</code>、
 * 估算滞后 <code>lag</code>（缓冲帧数 × 33ms + 往返延迟 / 2）与状态哈希核对结果（<code>sync ok</code> / <code>DESYNC</code>）。文字按游戏帧率着色（绿 ≥27、黄 15–27、红 &lt;15）。仅一个 <code>TextField</code>，无滤镜；隐藏时不监听帧事件。
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
    /** @private 游戏帧率达到该值显示绿色 */
    private static const GAME_GOOD:Number = 27;
    /** @private 游戏帧率达到该值显示黄色，否则红色 */
    private static const GAME_WARN:Number = 15;

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
    /** @private 上个窗口末的锁帧渲染累计次数 */
    private var _renderPrev:int;
    /** @private 上个窗口末的锁帧卡顿累计次数 */
    private var _stallPrev:int;
    /** @private 上上个窗口的渲染次数增量（与当前窗口合计约 1 秒） */
    private var _renderLast:int;
    /** @private 上上个窗口的卡顿次数增量 */
    private var _stallLast:int;

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
            _frames     = 0;
            _t0         = getTimer();
            _renderPrev = WebSessionCtrl.I.renderCount;
            _stallPrev  = WebSessionCtrl.I.stallCount;
            _renderLast = 0;
            _stallLast  = 0;
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

        var ctrl:WebSessionCtrl = WebSessionCtrl.I;
        var rc:int              = ctrl.renderCount - _renderPrev;
        var sc:int              = ctrl.stallCount - _stallPrev;
        var rt:int              = rc + _renderLast;
        var stallPct:int        = rt > 0 ? int((sc + _stallLast) * 100 / rt) : 0;
        _renderPrev             = ctrl.renderCount;
        _stallPrev              = ctrl.stallCount;
        _renderLast             = rc;
        _stallLast              = sc;

        var fps:Number  = _frames * 1000 / dt;
        var game:Number = rc > 0 ? (rc - sc) * 1000 / dt : fps;

        _txt.textColor = ctrl.desynced ? 0xff4444 : (game >= GAME_GOOD ? 0x00ff66 : (game >= GAME_WARN ? 0xffdd33 : 0xff4444));
        _txt.text      = 'game ' + game.toFixed(1)
                + ' | fps ' + fps.toFixed(1)
                + ' | stall ' + stallPct + '%'
                + ' | stage ' + int(_stage.frameRate)
                + '\nbuf ' + ctrl.bufferedFrames
                + ' | lag ~' + ctrl.lagMs + 'ms'
                + ' | ' + (ctrl.desynced ? 'DESYNC' : 'sync ok');
        reposition();
        _frames = 0;
        _t0     = now;
    }
}
}
