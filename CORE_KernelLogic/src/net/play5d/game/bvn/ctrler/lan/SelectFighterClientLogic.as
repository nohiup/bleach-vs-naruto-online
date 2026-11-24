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
import net.play5d.game.bvn.MainGame;
import net.play5d.game.bvn.data.GameData;
import net.play5d.game.bvn.data.lan.SelectFighterDataType;
import net.play5d.game.bvn.events.GameEvent;
import net.play5d.game.bvn.stage.LoadingStage;
import net.play5d.game.bvn.stage.SelectFighterStage;

/**
 * 局域网选人客户端逻辑（TCP 选人 / 出战顺序同步）。
 *
 * <p>服务端消息先进入待处理队列，对应场景就绪后再应用，避免本机较慢时消息被丢弃。
 * 本机出战资源加载完成时向服务端发送 <code>LOAD_DONE</code>；
 * 收到 <code>INDEX_FINISH</code> 后需本机加载完成才进入战斗。</p>
 *
 * @see SelectFighterServerLogic
 * @see SelectFighterPendingQueue
 */
public class SelectFighterClientLogic {
    /**
     * 构造选人客户端逻辑。
     */

    /** @private 发送 TCP 回调，签名 <code>function(data:Object):void</code> */
    private var _sendTCP:Function;
    /** @private 待处理的服务端消息 */
    private var _queue:SelectFighterPendingQueue;
    /** @private 已收到但等待本机加载完成的开战顺序 <code>[sort1, sort2]</code> */
    private var _finishOrders:Array;

    /**
     * 注册事件并禁用自动收尾。
     * @param sendTCP TCP 发送函数。
     */
    public function init(sendTCP:Function):void {
        _sendTCP = sendTCP;
        _queue   = new SelectFighterPendingQueue(applySelect);

        SelectFighterSyncPayload.disableAutoFinish();
        GameEvent.addEventListener(GameEvent.SELECT_FIGHTER_STEP, onSelectStep);
        GameEvent.addEventListener(GameEvent.SELECT_FIGHTER_INDEX, onSelectIndex);
        GameEvent.addEventListener(GameEvent.FIGHT_ASSETS_LOADED, onAssetsLoaded);
        GameEvent.addEventListener(GameEvent.ENTER_STAGE, onEnterStage);
    }

    /**
     * 移除事件监听。
     */
    public function dispose():void {
        GameEvent.removeEventListener(GameEvent.SELECT_FIGHTER_STEP, onSelectStep);
        GameEvent.removeEventListener(GameEvent.SELECT_FIGHTER_INDEX, onSelectIndex);
        GameEvent.removeEventListener(GameEvent.FIGHT_ASSETS_LOADED, onAssetsLoaded);
        GameEvent.removeEventListener(GameEvent.ENTER_STAGE, onEnterStage);

        if (_queue) {
            _queue.clear();
            _queue = null;
        }
        _finishOrders = null;
        _sendTCP      = null;
    }

    /**
     * 处理服务端选人包。
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
        case SelectFighterDataType.NEXT_STEP:
        case SelectFighterDataType.FIGHTER_FINISH:
        case SelectFighterDataType.INDEX:
        case SelectFighterDataType.INDEX_FINISH:
            if (_queue) {
                _queue.push(arr);
            }
            break;
        }

        return true;
    }

    /**
     * @private
     * 应用一条服务端消息；场景未就绪返回 <code>false</code> 以便稍后重试。
     */
    private function applySelect(arr:Array):Boolean {
        var selectStg:SelectFighterStage = MainGame.stageCtrl.currentStage as SelectFighterStage;
        var loadStg:LoadingStage         = MainGame.stageCtrl.currentStage as LoadingStage;

        switch (int(arr[1])) {
        case SelectFighterDataType.SELECT:
            if (!selectStg) {
                return false;
            }
            selectStg.setSelect(1, arr[2]);
            break;
        case SelectFighterDataType.NEXT_STEP:
            if (!selectStg) {
                return false;
            }
            selectStg.nextStep();
            break;
        case SelectFighterDataType.FIGHTER_FINISH:
            if (!selectStg) {
                return false;
            }
            GameData.I.selectMap = SelectFighterSyncPayload.unpackFighterFinish(
                    arr, GameData.I.p1Select, GameData.I.p2Select
            );
            selectStg.goLoadGame();
            break;
        case SelectFighterDataType.INDEX:
            if (!loadStg) {
                return false;
            }
            loadStg.setOrder(1, arr[2]);
            break;
        case SelectFighterDataType.INDEX_FINISH:
            if (!loadStg) {
                return false;
            }
            _finishOrders = [arr[2], arr[3]];
            tryGotoGame();
            break;
        }

        return true;
    }

    /**
     * @private
     * 已收到开战顺序且本机加载完成时进入战斗（只触发一次）。
     */
    private function tryGotoGame():void {
        if (!_finishOrders) {
            return;
        }

        var stg:LoadingStage = MainGame.stageCtrl.currentStage as LoadingStage;
        if (!stg || !stg.assetsLoaded) {
            return;
        }

        var orders:Array = _finishOrders;

        _finishOrders = null;
        stg.gotoGame(orders[0], orders[1]);
    }

    /** @private */
    private function onSelectStep(e:GameEvent):void {
        _sendTCP([SelectFighterDataType.KEY, SelectFighterDataType.SELECT, e.param]);
    }

    /** @private */
    private function onSelectIndex(e:GameEvent):void {
        _sendTCP([SelectFighterDataType.KEY, SelectFighterDataType.INDEX, e.param]);
    }

    /** @private 本机出战资源加载完成：通知服务端，并检查是否已在等待开战 */
    private function onAssetsLoaded(e:GameEvent):void {
        if (_sendTCP != null) {
            _sendTCP([SelectFighterDataType.KEY, SelectFighterDataType.LOAD_DONE]);
        }
        tryGotoGame();
    }

    /** @private 进入新场景：清理过期消息、重置回合状态并重试待处理消息 */
    private function onEnterStage(e:GameEvent):void {
        if (e.param == SelectFighterStage) {
            _finishOrders = null;
            _queue.dropLeading([SelectFighterDataType.INDEX, SelectFighterDataType.INDEX_FINISH]);
        }
        else if (e.param == LoadingStage) {
            _queue.dropLeading([
                SelectFighterDataType.SELECT,
                SelectFighterDataType.NEXT_STEP,
                SelectFighterDataType.FIGHTER_FINISH
            ]);
        }

        _queue.flush();
    }
}
}
