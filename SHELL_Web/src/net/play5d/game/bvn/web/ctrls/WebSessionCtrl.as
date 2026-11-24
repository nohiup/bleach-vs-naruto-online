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

package net.play5d.game.bvn.web.ctrls {
import flash.text.TextField;
import flash.text.TextFormat;
import flash.utils.ByteArray;

import net.play5d.game.bvn.MainGame;
import net.play5d.game.bvn.ctrler.game_ctrls.GameCtrl;
import net.play5d.game.bvn.ctrler.lan.LANUtils;
import net.play5d.game.bvn.ctrler.lan.LanClientSyncCore;
import net.play5d.game.bvn.ctrler.lan.LanGameMenuCtrl;
import net.play5d.game.bvn.ctrler.lan.LanServerSyncCore;
import net.play5d.game.bvn.ctrler.lan.LockFrameClientLogic;
import net.play5d.game.bvn.ctrler.lan.LockFrameLogic;
import net.play5d.game.bvn.ctrler.lan.LockFrameServerLogic;
import net.play5d.game.bvn.ctrler.lan.SelectFighterClientLogic;
import net.play5d.game.bvn.ctrler.lan.SelectFighterServerLogic;
import net.play5d.game.bvn.data.GameMode;
import net.play5d.game.bvn.events.GameEvent;
import net.play5d.game.bvn.interfaces.GameInterface;
import net.play5d.game.bvn.stage.GameStage;
import net.play5d.game.bvn.stage.LoadingStage;
import net.play5d.game.bvn.stage.MenuStage;
import net.play5d.game.bvn.stage.SelectFighterStage;
import net.play5d.game.bvn.ui.GameUI;
import net.play5d.game.bvn.ui.dialog.LANExitDialog;
import net.play5d.game.bvn.web.data.WebParams;
import net.play5d.game.bvn.web.input.InputManager;
import net.play5d.game.bvn.web.net.WebLanLink;
import net.play5d.game.bvn.web.utils.WebBridge;
import net.play5d.game.bvn.web.views.WebWaitState;

/**
 * 浏览器壳的联机会话：经中继连接对手，握手就绪后进入选人与锁帧对战。
 *
 * <p>流程对齐 PC 壳 <code>LANServerCtrl</code> / <code>LANClientCtrl</code>：房主绑定
 * <code>LanServerSyncCore</code> 与锁帧服务端逻辑，客户端绑定 <code>LanClientSyncCore</code> 与锁帧客户端逻辑；
 * 跳过 UDP 发现与主机列表。游戏资源加载完成且收到 <code>PEER_READY</code> 后，双方互发
 * <code>WEB_READY</code> 会话消息，都就绪才同时开始，避免一方尚未建好选人逻辑时丢包。</p>
 *
 * <p>对局结束（回到主菜单）、对手离开、连接断开或页面调用 <code>bvnLeave</code> 都会结束会话并关闭中继连接。</p>
 *
 * @example
 * <listing version="3.0">
 * WebSessionCtrl.I.connect();
 * // 资源加载完成后
 * WebSessionCtrl.I.onGameLoaded();
 * </listing>
 * @see net.play5d.game.bvn.web.net.WebLanLink
 */
public class WebSessionCtrl {
    /** @private 会话内就绪握手消息类型 */
    private static const MSG_READY:String = 'WEB_READY';

    /** @private */
    private static var _i:WebSessionCtrl;

    /**
     * 单例。
     * @return 会话控制器。
     */
    public static function get I():WebSessionCtrl {
        _i ||= new WebSessionCtrl();
        return _i;
    }

    /**
     * 锁帧对战是否进行中（选人、加载与战斗均算）。
     * @default false
     */
    public var active:Boolean;

    /** @private */
    private var _link:WebLanLink;
    /** @private */
    private var _isHost:Boolean;
    /** @private */
    private var _connected:Boolean;
    /** @private */
    private var _peerReady:Boolean;
    /** @private */
    private var _gameLoaded:Boolean;
    /** @private */
    private var _localReady:Boolean;
    /** @private */
    private var _remoteReady:Boolean;
    /** @private */
    private var _matchStarted:Boolean;
    /** @private */
    private var _matchEnded:Boolean;
    /** @private */
    private var _left:Boolean;
    /** @private */
    private var _selectServer:SelectFighterServerLogic;
    /** @private */
    private var _selectClient:SelectFighterClientLogic;
    /** @private */
    private var _serverLogic:LockFrameServerLogic;
    /** @private */
    private var _clientLogic:LockFrameClientLogic;
    /** @private */
    private var _serverSync:LanServerSyncCore;
    /** @private */
    private var _clientSync:LanClientSyncCore;
    /** @private */
    private var _delayText:TextField;

    /**
     * 本机是否为房主且对战进行中。
     * @return 房主对战中为 <code>true</code>。
     * @default false
     */
    public function get hostActive():Boolean {
        return active && _isHost;
    }

    /**
     * 本机是否为客户端且对战进行中。
     * @return 客户端对战中为 <code>true</code>。
     * @default false
     */
    public function get clientActive():Boolean {
        return active && !_isHost;
    }

    /**
     * 按 FlashVars 连接中继并注册页面退出回调；应在游戏资源开始加载前调用，以免握手超时。
     * @example
     * <listing version="3.0">
     * WebSessionCtrl.I.connect();
     * </listing>
     * @see net.play5d.game.bvn.web.data.WebParams
     */
    public function connect():void {
        var p:WebParams = WebParams.I;
        _isHost         = p.role == WebParams.ROLE_HOST;

        _link             = new WebLanLink();
        _link.onHelloOk   = onHelloOk;
        _link.onPeerReady = onPeerReady;
        _link.onPeerLeft  = onPeerLeft;
        _link.onClose     = onLinkClosed;
        _link.onSession   = onSession;
        _link.onInput     = onInput;
        _link.onRtt       = onRtt;
        _link.onError     = onLinkError;

        WebBridge.registerLeave(leave);

        _link.connect(p.relayHost, p.relayPort, p.token);
    }

    /**
     * 游戏资源加载完成后调用：显示等待界面，并在对手就绪时发出就绪握手。
     * @example
     * <listing version="3.0">
     * WebSessionCtrl.I.onGameLoaded();
     * </listing>
     */
    public function onGameLoaded():void {
        _gameLoaded = true;
        refreshWait();
        tryReady();
    }

    /**
     * 主动退出会话：结束对战、关闭中继连接并通知页面。
     * @example
     * <listing version="3.0">
     * WebSessionCtrl.I.leave();
     * </listing>
     */
    public function leave():void {
        finish('leave');
    }

    /** @private 发送会话消息（TCP 等价） */
    private function sendSession(data:Object):void {
        if (_link) {
            _link.sendSession(data);
        }
    }

    /** @private */
    private function onHelloOk(role:String):void {
        _isHost    = role == WebParams.ROLE_HOST;
        _connected = true;
        WebBridge.emit('connected', {role: role, nick: WebParams.I.nick});
        refreshWait();
    }

    /** @private */
    private function onPeerReady():void {
        _peerReady = true;
        WebBridge.emit('peerReady');
        refreshWait();
        tryReady();
    }

    /** @private */
    private function onPeerLeft():void {
        finish('peer_left');

        if (_isHost) {
            alertGame('alert.lan_server_ctrl.player_exit_title', 'alert.lan_server_ctrl.player_exit');
        }
        else {
            alertGame('alert.lan_client_ctrl.disconnect_title', 'alert.lan_client_ctrl.disconnect_host');
        }
    }

    /** @private */
    private function onLinkClosed():void {
        finish('socket_close');
        alertGame('alert.lan_client_ctrl.disconnect_title', 'alert.lan_client_ctrl.connection_interrupt');
    }

    /** @private */
    private function onLinkError(msg:String):void {
        WebBridge.emit('error', {msg: msg});
    }

    /** @private */
    private function onRtt(rtt:int):void {
        WebBridge.emit('ping', {rtt: rtt});
    }

    /** @private 会话消息：就绪握手优先，其余交给选人 / 同步逻辑 */
    private function onSession(data:Object):void {
        if (data && data.type == MSG_READY) {
            _remoteReady = true;
            tryStart();

            return;
        }

        if (!_matchStarted) {
            return;
        }

        if (_isHost) {
            if (_selectServer) {
                _selectServer.receiveSelect(data);
            }

            return;
        }

        if (_selectClient && _selectClient.receiveSelect(data)) {
            return;
        }

        if (_clientSync) {
            _clientSync.receiveSync(data);
        }
    }

    /** @private 锁帧输入：房主收客户端按键，客户端收服务端更新 */
    private function onInput(bytes:ByteArray):void {
        if (!_matchStarted) {
            return;
        }

        if (_isHost) {
            if (_serverLogic) {
                _serverLogic.receiveInput(bytes);
            }

            return;
        }

        if (_clientLogic) {
            if (_clientLogic.receiveSyncUpdate(bytes)) {
                return;
            }
            _clientLogic.receiveUpdate(bytes);
        }
    }

    /** @private 本机资源与对手席位都就绪后发出就绪握手 */
    private function tryReady():void {
        if (_localReady || !_gameLoaded || !_peerReady || _left) {
            return;
        }

        _localReady = true;
        sendSession({type: MSG_READY});
        tryStart();
    }

    /** @private 双方都就绪才开始 */
    private function tryStart():void {
        if (_localReady && _remoteReady && !_matchStarted && !_left) {
            startMatch();
        }
    }

    /** @private */
    private function startMatch():void {
        _matchStarted = true;
        active        = true;

        GameEvent.addEventListener(GameEvent.GAME_START, onGameStart);
        GameEvent.addEventListener(GameEvent.GAME_END, onGameEnd);
        GameEvent.addEventListener(GameEvent.ENTER_STAGE, onEnterStage);

        if (_isHost) {
            startHost();
        }
        else {
            startClient();
        }

        if (WebParams.I.mode == 'team') {
            GameMode.currentMode = GameMode.TEAM_VS_PEOPLE;
        }
        else {
            GameMode.currentMode = GameMode.SINGLE_VS_PEOPLE;
        }

        MainGame.I.goSelect();
    }

    /** @private 房主：对齐 LANServerCtrl.gameStart */
    private function startHost():void {
        GameInterface.instance.updateInputConfig();
        LockFrameLogic.I.initServer(renderHost);
        LANUtils.updateParams();

        _selectServer = new SelectFighterServerLogic();
        _selectServer.init(sendSession);

        _serverLogic = new LockFrameServerLogic();
        _serverLogic.init(_link, InputManager.I.socket_input_p1, InputManager.I.socket_input_p2);

        LanGameMenuCtrl.I.init(createExitDialog());

        _serverSync ||= new LanServerSyncCore();
        _serverSync.bind(_serverLogic, sendSession);
    }

    /** @private 客户端：对齐 LANClientCtrl.gameStart */
    private function startClient():void {
        _delayText                   = new TextField();
        _delayText.text              = '0ms';
        var tf:TextFormat            = new TextFormat();
        tf.color                     = 0xffffff;
        tf.size                      = 16;
        _delayText.defaultTextFormat = tf;
        MainGame.I.stage.addChild(_delayText);

        _selectClient = new SelectFighterClientLogic();
        _selectClient.init(sendSession);

        _clientLogic = new LockFrameClientLogic();
        _clientLogic.init(_link, InputManager.I.socket_input_p1, InputManager.I.socket_input_p2);

        _clientSync ||= new LanClientSyncCore(100);
        _clientSync.bind(_clientLogic, onSyncFatalError, _delayText);
        _link.syncCore = _clientSync;

        GameCtrl.I.autoEndRoundAble    = false;
        GameCtrl.I.autoStartAble       = false;
        SelectFighterStage.AUTO_FINISH = false;
        LoadingStage.AUTO_START_GAME   = false;

        GameInterface.instance.updateInputConfig();

        LockFrameLogic.I.initClient(renderClient);

        LanGameMenuCtrl.I.init(createExitDialog());

        LANUtils.updateParams();

        GameEvent.addEventListener(GameEvent.ROUND_START, onRoundStart);
    }

    /** @private */
    private function createExitDialog():LANExitDialog {
        return new LANExitDialog(
                function ():Boolean {
                    return clientActive;
                },
                function ():Boolean {
                    return hostActive;
                },
                leave,
                leave
        );
    }

    /** @private */
    private function renderHost():Boolean {
        if (_serverLogic && MainGame.stageCtrl.currentStage is GameStage) {
            return _serverLogic.render();
        }

        InputManager.I.socket_input_p1.freeRender();

        return true;
    }

    /** @private */
    private function renderClient():Boolean {
        if (_clientLogic && MainGame.stageCtrl.currentStage is GameStage) {
            return _clientLogic.render();
        }

        InputManager.I.socket_input_p2.freeRender();

        return true;
    }

    /** @private */
    private function onSyncFatalError():void {
        finish('sync_error');
        alertGame('alert.lan_client_ctrl.disconnect_title', 'alert.lan_client_ctrl.disconnect_error');
    }

    /** @private */
    private function onRoundStart(e:GameEvent):void {
        if (_clientSync) {
            _clientSync.onRoundStart();
        }
    }

    /** @private */
    private function onGameStart(e:GameEvent):void {
        _matchEnded = false;
        WebBridge.emit('matchStart', {role: _isHost ? WebParams.ROLE_HOST : WebParams.ROLE_CLIENT});
    }

    /** @private */
    private function onGameEnd(e:GameEvent):void {
        if (_matchEnded) {
            return;
        }

        _matchEnded = true;
        WebBridge.emit('matchEnd', {reason: 'finish'});
    }

    /** @private 对局结束后回到主菜单即视为本局会话完成 */
    private function onEnterStage(e:GameEvent):void {
        if (active && e.param == MenuStage) {
            finish('match_over');
        }
    }

    /** @private 结束会话：释放对战资源、关闭连接、通知页面并显示等待界面 */
    private function finish(reason:String):void {
        if (_left) {
            return;
        }

        _left = true;

        var matchRunning:Boolean = _matchStarted && !_matchEnded;

        disposeMatch();

        if (matchRunning) {
            _matchEnded = true;
            WebBridge.emit('matchEnd', {reason: reason});
        }

        if (_link) {
            _link.close();
            _link = null;
        }

        WebBridge.emit('disconnected', {reason: reason});

        refreshWait();
    }

    /** @private 释放选人 / 锁帧 / 同步逻辑，还原输入与游戏流程开关 */
    private function disposeMatch():void {
        GameEvent.removeEventListener(GameEvent.GAME_START, onGameStart);
        GameEvent.removeEventListener(GameEvent.GAME_END, onGameEnd);
        GameEvent.removeEventListener(GameEvent.ENTER_STAGE, onEnterStage);
        GameEvent.removeEventListener(GameEvent.ROUND_START, onRoundStart);

        if (!_matchStarted) {
            return;
        }

        active = false;

        if (_selectServer) {
            _selectServer.dispose();
            _selectServer = null;
        }
        if (_selectClient) {
            _selectClient.dispose();
            _selectClient = null;
        }

        if (_serverSync) {
            _serverSync.unbind();
        }
        if (_clientSync) {
            _clientSync.unbind();
        }

        if (_serverLogic) {
            _serverLogic.dispose();
            _serverLogic = null;
        }
        if (_clientLogic) {
            _clientLogic.dispose();
            _clientLogic = null;
        }

        if (_link) {
            _link.syncCore = null;
        }

        if (_delayText) {
            if (_delayText.parent) {
                _delayText.parent.removeChild(_delayText);
            }
            _delayText = null;
        }

        GameCtrl.I.autoEndRoundAble    = true;
        GameCtrl.I.autoStartAble       = true;
        SelectFighterStage.AUTO_FINISH = true;
        LoadingStage.AUTO_START_GAME   = true;

        GameInterface.instance.updateInputConfig();

        LockFrameLogic.I.dispose();

        LanGameMenuCtrl.I.dispose();
    }

    /** @private 按当前连接状态刷新等待界面文案；对战中不动 */
    private function refreshWait():void {
        if (!_gameLoaded || (_matchStarted && !_left)) {
            return;
        }

        var key:String;
        if (_left) {
            key = 'txt.web_session_ctrl.left';
        }
        else if (!_connected) {
            key = 'txt.web_session_ctrl.connecting';
        }
        else if (!_peerReady) {
            key = 'txt.web_session_ctrl.waiting_peer';
        }
        else {
            key = 'txt.web_session_ctrl.waiting_ready';
        }

        var wait:WebWaitState = MainGame.stageCtrl.currentStage as WebWaitState;
        if (!wait) {
            wait = new WebWaitState();
            MainGame.stageCtrl.goStage(wait);
        }
        wait.text = GetLang(key);
    }

    /** @private 游戏已初始化时弹出提示 */
    private function alertGame(titleKey:String, msgKey:String):void {
        if (!_gameLoaded) {
            return;
        }

        GameUI.alert(GetLang(titleKey), GetLang(msgKey));
    }
}
}
