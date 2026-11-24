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

package {
import flash.display.Sprite;
import flash.events.Event;
import flash.events.KeyboardEvent;
import flash.ui.Keyboard;

import net.play5d.game.bvn.GameQuality;
import net.play5d.game.bvn.MainGame;
import net.play5d.game.bvn.ctrler.AssetManager;
import net.play5d.game.bvn.data.GameData;
import net.play5d.game.bvn.debug.Debugger;
import net.play5d.game.bvn.interfaces.GameInterface;
import net.play5d.game.bvn.ui.GameUI;
import net.play5d.game.bvn.ui.UIUtils;
import net.play5d.game.bvn.utils.AssetLoader;
import net.play5d.game.bvn.utils.GameLogger;
import net.play5d.game.bvn.utils.ResUtils;
import net.play5d.game.bvn.utils.SwfLib;
import net.play5d.game.bvn.utils.URL;
import net.play5d.game.bvn.web.GameInterfaceManager;
import net.play5d.game.bvn.web.ctrls.WebSessionCtrl;
import net.play5d.game.bvn.web.data.WebParams;
import net.play5d.game.bvn.web.utils.WebBridge;
import net.play5d.game.bvn.web.utils.WebLoger;

/**
 * 浏览器（Flash Player / Ruffle，非 AIR）入口。
 *
 * <p>读取 FlashVars 后先连接中继，再按 PC 壳的顺序初始化并加载游戏；资源就绪后进入联机等待界面，
 * 与对手握手完成即进入选人。未带 <code>web=1</code> 时按离线模式进入标题界面，便于本地调试。</p>
 *
 * @see net.play5d.game.bvn.web.ctrls.WebSessionCtrl
 */
[SWF(width='800', height='600', frameRate='30', backgroundColor='#000000')]
public class WebLaunch extends Sprite {
    /**
     * 构造入口并等待添加到舞台。
     */
    public function WebLaunch() {
        if (stage) {
            initialize();
        }
        else {
            addEventListener(Event.ADDED_TO_STAGE, initialize);
        }
    }

    /** @private */
    private var _mainGame:MainGame;
    /** @private */
    private var _assetLoader:AssetLoader = new AssetLoader();

    /** @private */
    private function initialize(e:Event = null):void {
        GameLogger.setLoger(new WebLoger());
        GameLogger.log('init...');

        removeEventListener(Event.ADDED_TO_STAGE, initialize);
        STAGE = stage;

        WebParams.I.read(loaderInfo.parameters);

        ResUtils.swfLib = new SwfLib();
        AssetManager.I.setAssetLoader(_assetLoader);

        GameInterface.instance = new GameInterfaceManager();

        GameUI.BITMAP_UI = true;

        GameData.I.config.AI_level     = 1;
        GameData.I.config.quality      = GameQuality.LOW;
        GameData.I.config.keyInputMode = 1;

        URL.MARK = 'bvn_web' + MainGame.VERSION;

        // 先连中继：资源加载耗时，晚连会错过大厅发放 token 的 15 秒认领窗口
        if (WebParams.I.web) {
            WebSessionCtrl.I.connect();
        }

        buildGame();
    }

    /** @private */
    private function buildGame():void {
        GameLogger.log('buildGame');

        _mainGame = new MainGame();
        _mainGame.initialize(this, stage, function ():void {
            _mainGame.goLanguage(function ():void {
                TraceLang('debug.trace.data.root_sprite.current_font', {fontName: FONT.fontName});
                UIUtils.LOCK_FONT = FONT.fontName;

                GameData.I.saveData();
                _mainGame.initializeLoad(initBackHandler, initFailHandler);
            });
        }, initFailHandler);

        if (Debugger.DEBUG_ENABLED) {
            Debugger.initDebug(stage);
        }

        stage.addEventListener(KeyboardEvent.KEY_DOWN, keyDownHandler);
    }

    /** @private */
    private function initBackHandler():void {
        GameLogger.log('init ok');

        if (WebParams.I.web) {
            WebSessionCtrl.I.onGameLoaded();
        }
        else {
            _mainGame.goLogo();
        }
    }

    /** @private */
    private function initFailHandler(msg:String = null):void {
        GameLogger.log('init fail');
        WebBridge.emit('error', {msg: msg || 'init fail'});
    }

    /** @private */
    private function keyDownHandler(e:KeyboardEvent):void {
        if (e.keyCode == Keyboard.ESCAPE) {
            e.preventDefault();
        }
    }
}
}
