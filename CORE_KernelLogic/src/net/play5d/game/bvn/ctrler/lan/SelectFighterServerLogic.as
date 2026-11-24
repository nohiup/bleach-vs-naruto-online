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

import net.play5d.game.bvn.MainGame;
import net.play5d.game.bvn.data.GameData;
import net.play5d.game.bvn.data.lan.SelectFighterDataType;
import net.play5d.game.bvn.events.GameEvent;
import net.play5d.game.bvn.stage.LoadingStage;
import net.play5d.game.bvn.stage.SelectFighterStage;

/**
 * 局域网选人服务端逻辑（汇总双方选择并推进步骤）。
 *
 * <p>开战握手：客户端的选人 / 出战顺序消息先进入待处理队列，场景就绪后再应用；
 * 仅当服务端自身加载完成、客户端已发 <code>LOAD_DONE</code> 且双方出战顺序都已确定时，
 * 才发送 <code>INDEX_FINISH</code> 并进入战斗。</p>
 *
 * @see SelectFighterClientLogic
 * @see SelectFighterPendingQueue
 */
public class SelectFighterServerLogic {
    /**
     * 构造选人服务端逻辑。
     */

    /** @private */
    private var _timeout:int;
    /** @private 发送 TCP 回调，签名 <code>function(data:Object):void</code> */
    private var _sendTCP:Function;
    /** @private 待处理的客户端消息 */
    private var _queue:SelectFighterPendingQueue;
    /** @private 客户端是否已完成出战资源加载 */
    private var _clientLoaded:Boolean;
    /** @private 本轮是否已安排开战 */
    private var _fightScheduled:Boolean;

    /**
     * 注册事件并禁用自动收尾。
     * @param sendTCP TCP 发送函数。
     */
    public function init(sendTCP:Function):void {
        _sendTCP = sendTCP;
        _queue   = new SelectFighterPendingQueue(applySelect);

        SelectFighterSyncPayload.disableAutoFinish();

        GameEvent.addEventListener(GameEvent.SELECT_FIGHTER_STEP, onSelectStep);
        GameEvent.addEventListener(GameEvent.SELECT_FIGHTER_FINISH, onSelectFinish);
        GameEvent.addEventListener(GameEvent.SELECT_FIGHTER_INDEX, onSelectFighterIndex);
        GameEvent.addEventListener(GameEvent.FIGHT_ASSETS_LOADED, onAssetsLoaded);
        GameEvent.addEventListener(GameEvent.ENTER_STAGE, onEnterStage);
    }

    /**
     * 移除事件监听。
     */
    public function dispose():void {
        GameEvent.removeEventListener(GameEvent.SELECT_FIGHTER_STEP, onSelectStep);
        GameEvent.removeEventListener(GameEvent.SELECT_FIGHTER_FINISH, onSelectFinish);
        GameEvent.removeEventListener(GameEvent.SELECT_FIGHTER_INDEX, onSelectFighterIndex);
        GameEvent.removeEventListener(GameEvent.FIGHT_ASSETS_LOADED, onAssetsLoaded);
        GameEvent.removeEventListener(GameEvent.ENTER_STAGE, onEnterStage);

        clearTimeout(_timeout);
        if (_queue) {
            _queue.clear();
            _queue = null;
        }
        _sendTCP = null;
    }

    /**
     * 处理客户端选人包。
     * @param data 载荷。
     * @return 已识别为选人协议时为 <code>true</code>。
     */
    public function receiveSelect(data:Object):Boolean {
        var arr:Array = data as Array;
        if (!arr || arr[0] != SelectFighterDataType.KEY) {
            return false;
        }

        switch (int(arr[1])) {
        case SelectFighterDataType.SELECT:
        case SelectFighterDataType.INDEX:
            if (_queue) {
                _queue.push(arr);
            }
            break;
        case SelectFighterDataType.LOAD_DONE:
            _clientLoaded = true;
            tryStartFight();
            break;
        }

        return true;
    }

    /**
     * @private
     * 应用一条客户端消息；场景未就绪返回 <code>false</code> 以便稍后重试。
     */
    private function applySelect(arr:Array):Boolean {
        switch (int(arr[1])) {
        case SelectFighterDataType.SELECT:
            var stg:SelectFighterStage = MainGame.stageCtrl.currentStage as SelectFighterStage;
            if (!stg) {
                return false;
            }
            stg.setSelect(2, arr[2]);
            checkSelectFinish();
            break;
        case SelectFighterDataType.INDEX:
            var stg2:LoadingStage = MainGame.stageCtrl.currentStage as LoadingStage;
            if (!stg2) {
                return false;
            }
            stg2.setOrder(2, arr[2]);
            tryStartFight();
            break;
        }

        return true;
    }

    /** @private */
    private function checkSelectFinish():void {
        var stg:SelectFighterStage = MainGame.stageCtrl.currentStage as SelectFighterStage;
        if (stg && stg.p1SelectFinish && stg.p2SelectFinish) {
            clearTimeout(_timeout);
            _timeout = setTimeout(function ():void {
                if (_sendTCP == null) {
                    return;
                }
                _sendTCP([SelectFighterDataType.KEY, SelectFighterDataType.NEXT_STEP]);
                stg.nextStep();
            }, 1000);
        }
    }

    /**
     * @private
     * 服务端加载完成、客户端加载完成、双方顺序确定三者齐备时开战（每轮只触发一次）。
     */
    private function tryStartFight():void {
        if (_fightScheduled) {
            return;
        }

        var stg:LoadingStage = MainGame.stageCtrl.currentStage as LoadingStage;
        if (!stg || !stg.assetsLoaded || !_clientLoaded || !stg.selectFinish()) {
            return;
        }

        _fightScheduled = true;

        setTimeout(function ():void {
            if (_sendTCP == null || MainGame.stageCtrl.currentStage != stg) {
                return;
            }

            var orders:Array = stg.getSort();

            _sendTCP([SelectFighterDataType.KEY, SelectFighterDataType.INDEX_FINISH, orders[0], orders[1]]);
            stg.gotoGame(orders[0], orders[1]);
        }, 1000);
    }

    /** @private */
    private function onSelectStep(e:GameEvent):void {
        _sendTCP([SelectFighterDataType.KEY, SelectFighterDataType.SELECT, e.param]);
        checkSelectFinish();
    }

    /** @private */
    private function onSelectFinish(e:GameEvent):void {
        _sendTCP(SelectFighterSyncPayload.packFighterFinish(
                GameData.I.p1Select, GameData.I.p2Select, GameData.I.selectMap
        ));

        var stg:SelectFighterStage = MainGame.stageCtrl.currentStage as SelectFighterStage;
        if (stg) {
            stg.goLoadGame();
        }
    }

    /** @private */
    private function onSelectFighterIndex(e:GameEvent):void {
        _sendTCP([SelectFighterDataType.KEY, SelectFighterDataType.INDEX, e.param]);
        tryStartFight();
    }

    /** @private 本机出战资源加载完成 */
    private function onAssetsLoaded(e:GameEvent):void {
        tryStartFight();
    }

    /** @private 进入新场景：清理过期消息、重置回合状态并重试待处理消息 */
    private function onEnterStage(e:GameEvent):void {
        if (e.param == SelectFighterStage) {
            _clientLoaded   = false;
            _fightScheduled = false;
            _queue.dropLeading([SelectFighterDataType.INDEX]);
        }
        else if (e.param == LoadingStage) {
            _queue.dropLeading([SelectFighterDataType.SELECT]);
        }

        _queue.flush();
    }
}
}
