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
import flash.display.DisplayObject;
import flash.display.Sprite;
import flash.text.TextField;
import flash.text.TextFieldAutoSize;
import flash.text.TextFormat;
import flash.text.TextFormatAlign;

import net.play5d.game.bvn.GameConfig;
import net.play5d.game.bvn.ui.UIUtils;
import net.play5d.kyo.stage.IStage;

/**
 * 联机等待场景：黑底居中一行状态文字（连接中 / 等待对手 / 已离开）。
 *
 * @example
 * <listing version="3.0">
 * var wait:WebWaitState = new WebWaitState();
 * wait.text = 'waiting...';
 * MainGame.stageCtrl.goStage(wait);
 * </listing>
 * @see net.play5d.kyo.stage.IStage
 */
public class WebWaitState implements IStage {
    /** @private */
    private var _ui:Sprite;
    /** @private */
    private var _txt:TextField;
    /** @private */
    private var _text:String = '';

    /**
     * @inheritDoc
     */
    public function get display():DisplayObject {
        return _ui;
    }

    /**
     * 状态文字；场景构建前后设置均可。
     * @default ''
     */
    public function get text():String {
        return _text;
    }

    /** @private */
    public function set text(v:String):void {
        _text = v;
        if (_txt) {
            _txt.text = v;
            _txt.y    = (GameConfig.GAME_SIZE.y - _txt.height) / 2;
        }
    }

    /**
     * @inheritDoc
     */
    public function build():void {
        _ui = new Sprite();
        _ui.graphics.beginFill(0x000000);
        _ui.graphics.drawRect(0, 0, GameConfig.GAME_SIZE.x, GameConfig.GAME_SIZE.y);
        _ui.graphics.endFill();

        var tf:TextFormat = new TextFormat();
        tf.color          = 0xffffff;
        tf.size           = 24;
        tf.align          = TextFormatAlign.CENTER;
        tf.font           = UIUtils.LOCK_FONT || UIUtils.DEFAULT_FONT;

        _txt                   = new TextField();
        _txt.defaultTextFormat = tf;
        _txt.width             = GameConfig.GAME_SIZE.x;
        _txt.wordWrap          = true;
        _txt.autoSize          = TextFieldAutoSize.CENTER;
        _txt.selectable        = false;
        _txt.mouseEnabled      = false;
        _ui.addChild(_txt);

        text = _text;
    }

    /**
     * @inheritDoc
     */
    public function afterBuild():void {
    }

    /**
     * @inheritDoc
     */
    public function destroy(back:Function = null):void {
        _txt = null;
        _ui  = null;
    }
}
}
