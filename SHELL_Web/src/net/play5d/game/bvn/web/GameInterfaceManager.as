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

package net.play5d.game.bvn.web {
import flash.display.DisplayObject;
import flash.display.Sprite;
import flash.display.StageQuality;
import flash.events.MouseEvent;
import flash.utils.ByteArray;

import net.play5d.game.bvn.GameConfig;
import net.play5d.game.bvn.GameQuality;
import net.play5d.game.bvn.MainGame;
import net.play5d.game.bvn.data.GameData;
import net.play5d.game.bvn.data.vos.ConfigVO;
import net.play5d.game.bvn.input.GameInputType;
import net.play5d.game.bvn.interfaces.IExtendConfig;
import net.play5d.game.bvn.interfaces.IFighterActionCtrl;
import net.play5d.game.bvn.interfaces.IGameInput;
import net.play5d.game.bvn.interfaces.IGameInterface;
import net.play5d.game.bvn.utils.CreditsSpriteUtil;
import net.play5d.game.bvn.utils.URL;
import net.play5d.game.bvn.web.ctrls.WebSessionCtrl;
import net.play5d.game.bvn.web.data.ExtendConfig;
import net.play5d.game.bvn.web.data.WebParams;
import net.play5d.game.bvn.web.input.InputManager;
import net.play5d.kyo.storage.KyoSharedObject;

/**
 * 浏览器壳的游戏接口：存档走 <code>SharedObject</code>，仅键盘输入，菜单为离线模式子集。
 *
 * <p>联机对局不经过主菜单；联机锁帧期间输入切到 <code>GameSocketInput</code>，逻辑对齐 PC 壳。</p>
 *
 * @see net.play5d.game.bvn.interfaces.IGameInterface
 * @see WebSessionCtrl
 */
public class GameInterfaceManager implements IGameInterface {
    /** @private 存档在 SharedObject 中的名称 */
    private static const SAVE_ID:String = 'bvn_web_save';
    /** @private 存档 JSON 所在字段 */
    private static const SAVE_KEY:String = 'json';

    /** @private */
    private var _extendsConfig:ExtendConfig = new ExtendConfig();

    /**
     * @inheritDoc
     */
    public function initTitleUI(ui:DisplayObject):void {
        var logomc:Sprite = (
                            ui as Sprite
                            ).getChildByName('logo_mc') as Sprite;
        if (!logomc) {
            return;
        }
        logomc.visible    = true;
        var logo5d:Sprite = logomc.getChildByName('logo_site') as Sprite;
        if (logo5d) {
            logo5d.buttonMode = true;
            logo5d.addEventListener(MouseEvent.MOUSE_UP, URL.website, false, 0, true);
        }
        var logobbs:Sprite = logomc.getChildByName('logo_android') as Sprite;
        if (logobbs) {
            logobbs.buttonMode = true;
            logobbs.addEventListener(MouseEvent.MOUSE_UP, URL.bbs, false, 0, true);
        }
    }

    /**
     * @inheritDoc
     */
    public function moreGames():void {
        URL.website();
    }

    /**
     * @inheritDoc
     */
    public function submitScore(score:int):void {
    }

    /**
     * @inheritDoc
     */
    public function showRank():void {
    }

    /**
     * @inheritDoc
     */
    public function saveGame(data:Object):void {
        // 联机期间生命 / 时间为房主覆盖值，不写入玩家存档
        if (WebSessionCtrl.I.settingsOverridden) {
            return;
        }

        var so:Object = {};
        so[SAVE_KEY]  = JSON.stringify(data);

        try {
            KyoSharedObject.save(SAVE_ID, so);
        }
        catch (e:Error) {
            trace('saveGame', e);
        }
    }

    /**
     * @inheritDoc
     */
    public function loadGame():Object {
        try {
            var so:Object = KyoSharedObject.load(SAVE_ID);
            if (!so || !so[SAVE_KEY]) {
                return null;
            }

            return JSON.parse(so[SAVE_KEY]);
        }
        catch (e:Error) {
            trace('loadGame', e);
        }

        return null;
    }

    /**
     * @inheritDoc
     */
    public function getFighterCtrl(player:int):IFighterActionCtrl {
        return null;
    }

    /**
     * @inheritDoc
     */
    public function getGameMenu():Array {
        var menu:Array = [
            {
                txt: 'TEAM PLAY', cn: GetLang('txt.game_interface.team_play'), children: [
                    {txt: 'TEAM ACRADE', cn: GetLang('txt.game_interface.team_play_acrade')},
                    {txt: 'TEAM VS PEOPLE', cn: GetLang('txt.game_interface.team_play_vs_people')},
                    {txt: 'TEAM VS CPU', cn: GetLang('txt.game_interface.team_play_vs_CPU')},
                    {txt: 'TEAM WATCH', cn: GetLang('txt.game_interface.team_play_watch')}
                ]
            },

            {
                txt: 'SINGLE PLAY', cn: GetLang('txt.game_interface.single_play'), children: [
                    {txt: 'SINGLE ACRADE', cn: GetLang('txt.game_interface.single_play_acrade')},
                    {txt: 'SINGLE VS PEOPLE', cn: GetLang('txt.game_interface.single_play_vs_people')},
                    {txt: 'SINGLE VS CPU', cn: GetLang('txt.game_interface.single_play_vs_CPU')},
                    {txt: 'SINGLE WATCH', cn: GetLang('txt.game_interface.single_play_watch')}
                ]
            },

            {
                txt: 'MUSOU PLAY', cn: GetLang('txt.game_interface.musou_play'), children: [
                    {txt: 'MUSOU ACRADE', cn: GetLang('txt.game_interface.musou_acrade')}
                ]
            },

            {txt: 'OPTION', cn: GetLang('txt.game_interface.option')},
            {txt: 'TRAINING', cn: GetLang('txt.game_interface.training')},
            {txt: 'CREDITS', cn: GetLang('txt.game_interface.credits')}
        ];

        if (WebParams.I.web) {
            menu.push({
                txt: 'LEAVE', cn: GetLang('txt.game_interface_manager.web_leave'), func: function ():void {
                    WebSessionCtrl.I.leave();
                }
            });
        }

        return menu;
    }

    /**
     * @inheritDoc
     */
    public function getSettingMenu():Array {
        return [
            {txt: 'P1 KEY SET', cn: GetLang('txt.set_btn_group.p1_key_set')},
            {txt: 'P2 KEY SET', cn: GetLang('txt.set_btn_group.p2_key_set')},
            {
                txt      : 'COM LEVEL', cn: GetLang('txt.set_btn_group.com_level'),
                options  : [
                    {label: 'VERY EASY', cn: GetLang('txt.set_btn_group.com_level_very_easy'), value: 1},
                    {label: 'EASY', cn: GetLang('txt.set_btn_group.com_level_easy'), value: 2},
                    {label: 'NORMAL', cn: GetLang('txt.set_btn_group.com_level_normal'), value: 3},
                    {label: 'HARD', cn: GetLang('txt.set_btn_group.com_level_hard'), value: 4},
                    {label: 'VERY HARD', cn: GetLang('txt.set_btn_group.com_level_very_hard'), value: 5},
                    {label: 'HELL', cn: GetLang('txt.set_btn_group.com_level_hell'), value: 6}
                ],
                optoinKey: 'AI_level'
            },
            {
                txt      : 'OPERATE MODE', cn: GetLang('txt.set_btn_group.operate_mode'),
                options  : [
                    {label: 'NORMAL', cn: GetLang('txt.set_btn_group.operate_normal'), value: 0},
                    {label: 'CLASSIC', cn: GetLang('txt.set_btn_group.operate_classic'), value: 1}
                ],
                optoinKey: 'keyInputMode'
            },
            {
                txt      : 'LIFE', cn: GetLang('txt.set_btn_group.life'),
                options  : [
                    {label: '50%', cn: '50%', value: 0.5},
                    {label: '100%', cn: '100%', value: 1},
                    {label: '200%', cn: '200%', value: 2},
                    {label: '300%', cn: '300%', value: 3},
                    {label: '500%', cn: '500%', value: 5}
                ],
                optoinKey: 'fighterHP'
            },
            {
                txt      : 'TIME', cn: GetLang('txt.set_btn_group.time'),
                options  : [
                    {label: '30s', cn: GetLang('txt.set_btn_group.time_30'), value: 30},
                    {label: '60s', cn: GetLang('txt.set_btn_group.time_60'), value: 60},
                    {label: '90s', cn: GetLang('txt.set_btn_group.time_90'), value: 90},
                    {label: '∞', cn: GetLang('txt.set_btn_group.time_unlimited'), value: -1}
                ],
                optoinKey: 'fightTime'
            },
            {
                txt      : 'SOUND', cn: GetLang('txt.set_btn_group.sound'),
                options  : [
                    {label: '0%', cn: '0%', value: 0},
                    {label: '10%', cn: '10%', value: 0.1},
                    {label: '30%', cn: '30%', value: 0.3},
                    {label: '50%', cn: '50%', value: 0.5},
                    {label: '70%', cn: '70%', value: 0.7},
                    {label: '100%', cn: '100%', value: 1}
                ],
                optoinKey: 'soundVolume'
            },
            {
                txt      : 'BGM', cn: GetLang('txt.set_btn_group.bgm'),
                options  : [
                    {label: '0%', cn: '0%', value: 0},
                    {label: '10%', cn: '10%', value: 0.1},
                    {label: '30%', cn: '30%', value: 0.3},
                    {label: '50%', cn: '50%', value: 0.5},
                    {label: '70%', cn: '70%', value: 0.7},
                    {label: '100%', cn: '100%', value: 1}
                ],
                optoinKey: 'bgmVolume'
            },
            {
                txt      : 'QUALITY', cn: GetLang('txt.set_btn_group.quality'),
                options  : [
                    {label: 'LOW', cn: GetLang('txt.set_btn_group.quality_low'), value: GameQuality.LOW},
                    {label: 'MEDIUM', cn: GetLang('txt.set_btn_group.quality_medium'), value: GameQuality.MEDIUM},
                    {label: 'HIGH', cn: GetLang('txt.set_btn_group.quality_high'), value: GameQuality.HIGH},
                    {label: 'BEST', cn: GetLang('txt.set_btn_group.quality_best'), value: GameQuality.BEST}
                ],
                optoinKey: 'quality'
            },
            {
                txt      : 'SHOW HP', cn: GetLang('txt.set_btn_group.show_hp'),
                options  : [
                    {label: 'SHOW', cn: GetLang('txt.set_btn_group.hp_show'), value: true},
                    {label: 'HIDE', cn: GetLang('txt.set_btn_group.hp_hide'), value: false}
                ],
                optoinKey: 'isShowHp'
            }
        ];
    }

    /**
     * @inheritDoc
     */
    public function getGameInput(type:String):Vector.<IGameInput> {
        var vec:Vector.<IGameInput> = new Vector.<IGameInput>();

        switch (type) {
        case GameInputType.MENU:
            vec.push(InputManager.I.key_menu);
            break;
        case GameInputType.P1:
            vec.push(InputManager.I.key_p1);
            vec.push(InputManager.I.socket_input_p1);
            break;
        case GameInputType.P2:
            vec.push(InputManager.I.key_p2);
            vec.push(InputManager.I.socket_input_p2);
            break;
        default:
            return null;
        }

        return vec;
    }

    /**
     * @inheritDoc
     */
    public function getConfigExtend():IExtendConfig {
        return _extendsConfig;
    }

    /**
     * 构建对局后回调；网页壳为空实现。
     *
     * <p>不调用 <code>MapLayerCacheUtil</code>：其设置的 <code>cacheAsBitmapMatrix</code> 仅 AIR 可用，
     * 在 Flash Player / Ruffle 中抛出 ReferenceError #1056，导致对局构建中断。</p>
     */
    public function afterBuildGame():void {
    }

    /**
     * 更新输入设置：联机锁帧期间键盘仅作为本机采集源，对局输入统一走 Socket 通道。
     * @return 恒为 <code>true</code>。
     */
    public function updateInputConfig():Boolean {
        var session:WebSessionCtrl = WebSessionCtrl.I;

        if (session.hostActive || session.clientActive) {
            // 锁帧同步：本机按键由 GameSocketInput 采集并经中继对齐后再回写
            InputManager.I.key_menu.enabled = false;
            InputManager.I.key_p1.enabled   = false;
            InputManager.I.key_p2.enabled   = false;

            InputManager.I.socket_input_p1.enabled = true;
            InputManager.I.socket_input_p2.enabled = true;

            if (session.hostActive) {
                InputManager.I.socket_input_p1.setInputers([InputManager.I.key_p1]);
            }

            if (session.clientActive) {
                InputManager.I.key_p2.setConfig(GameData.I.config.key_p1);
                InputManager.I.socket_input_p2.setInputers([InputManager.I.key_p2]);
            }

            return true;
        }

        InputManager.I.key_menu.setConfig(GameData.I.config.key_menu);
        InputManager.I.key_p1.setConfig(GameData.I.config.key_p1);
        InputManager.I.key_p2.setConfig(GameData.I.config.key_p2);

        InputManager.I.socket_input_p1.enabled = false;
        InputManager.I.socket_input_p2.enabled = false;

        return true;
    }

    /**
     * @inheritDoc
     */
    public function applyConfig(config:Object):void {
        var cfg:ConfigVO = config as ConfigVO;
        if (!cfg) {
            return;
        }

        switch (cfg.quality) {
        case GameQuality.BEST:
            MainGame.I.stage.quality = StageQuality.HIGH_16X16;
            MainGame.I.setFPS(60);
            GameConfig.FPS_SHINE_EFFECT = 60;
            break;
        case GameQuality.HIGHER:
            MainGame.I.stage.quality = StageQuality.HIGH_8X8;
            MainGame.I.setFPS(60);
            GameConfig.FPS_SHINE_EFFECT = 30;
            break;
        case GameQuality.HIGH:
            MainGame.I.stage.quality = StageQuality.HIGH;
            MainGame.I.setFPS(60);
            GameConfig.FPS_SHINE_EFFECT = 30;
            break;
        case GameQuality.MEDIUM:
            MainGame.I.stage.quality = StageQuality.MEDIUM;
            MainGame.I.setFPS(60);
            GameConfig.FPS_SHINE_EFFECT = 15;
            break;
        case GameQuality.LOW:
            MainGame.I.stage.quality = StageQuality.LOW;
            MainGame.I.setFPS(30);
            GameConfig.FPS_SHINE_EFFECT = 10;
            break;
        }
    }

    /**
     * @inheritDoc
     */
    public function getCredits(creditsInfo:String):Sprite {
        return CreditsSpriteUtil.build(creditsInfo, 'txt.game_interface_manager.credits_footer');
    }

    /**
     * @inheritDoc
     */
    public function checkFile(url:String, file:ByteArray):Boolean {
        return true;
    }

    /**
     * @inheritDoc
     */
    public function addMusouMoney(back:Function):void {
        back(100 + Math.random() * 200);
    }
}
}
