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
import flash.utils.getTimer;

import net.play5d.game.bvn.GameConfig;
import net.play5d.game.bvn.MainGame;
import net.play5d.game.bvn.ctrler.game_ctrls.GameCtrl;
import net.play5d.game.bvn.ctrler.lan.LANUtils;
import net.play5d.game.bvn.ctrler.lan.LanClientSyncCore;
import net.play5d.game.bvn.ctrler.lan.LanGameMenuCtrl;
import net.play5d.game.bvn.ctrler.lan.LanServerSyncCore;
import net.play5d.game.bvn.ctrler.lan.LanStallMonitor;
import net.play5d.game.bvn.ctrler.lan.LockFrameLogic;
import net.play5d.game.bvn.ctrler.lan.LockFrameRelayLogic;
import net.play5d.game.bvn.ctrler.lan.SelectFighterClientLogic;
import net.play5d.game.bvn.ctrler.lan.SelectFighterServerLogic;
import net.play5d.game.bvn.data.GameData;
import net.play5d.game.bvn.data.GameMode;
import net.play5d.game.bvn.data.TeamID;
import net.play5d.game.bvn.data.vos.ConfigVO;
import net.play5d.game.bvn.data.lan.LanNetConfig;
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
 * <code>LanServerSyncCore</code>，客户端绑定 <code>LanClientSyncCore</code>；对战锁帧两端对称，
 * 均使用 <code>LockFrameRelayLogic</code>（中继节拍，<code>LanNetConfig.relayPaced</code>），
 * 由中继按固定节奏下发帧流；跳过 UDP 发现与主机列表。游戏资源加载完成且收到 <code>PEER_READY</code> 后，双方互发
 * <code>WEB_READY</code> 会话消息，都就绪才同时开始，避免一方尚未建好选人逻辑时丢包。</p>
 *
 * <p>一局正常结束只上报 <code>matchEnd</code>，会话保持：游戏沿用 LAN 流程回到选人，可用同一套对局设置再战；
 * 房主下发的生命 / 时间在会话期间每次进入选人 / 对战场景都会重新套用，仅在会话真正结束时还原玩家本地设置。
 * 对手离开、连接断开、卡顿超时、同步错误、页面调用 <code>bvnLeave</code> 或中途回到主菜单上报
 * <code>disconnected</code>。卡顿经 <code>stall</code> / <code>resume</code> 上报，失同步经 <code>desync</code>
 * 上报（不中断对局）。</p>
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
    /** @private 房主下发对局设置（生命 / 时间 / 输入延迟）的会话消息类型 */
    private static const MSG_SETTINGS:String = 'WEB_SETTINGS';
    /** @private 状态哈希会话消息类型（两端互发，用于失同步检测） */
    private static const MSG_HASH:String = 'WEB_HASH';
    /** @private 状态哈希环形缓存保留条数 */
    private static const HASH_RING:int = 10;
    /** @private 单帧中继逻辑帧时长估算（毫秒，约 30 FPS） */
    private static const FRAME_MS:int = 33;
    /** @private stall 事件最小上报间隔（毫秒） */
    private static const STALL_EMIT_MS:int = 250;

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
    /** @private 客户端是否已收到房主的对局设置（房主恒为 <code>true</code>） */
    private var _settingsReceived:Boolean;
    /** @private 本场对局生命比例 */
    private var _matchHp:Number = WebParams.HP_DEFAULT;
    /** @private 本场对局回合时间 */
    private var _matchTime:int = WebParams.TIME_DEFAULT;
    /** @private 本场对局输入延迟（帧） */
    private var _matchDelay:int = 3;
    /** @private 房主是否已下发 <code>WEB_SETTINGS</code>（此后不再接受页面更新） */
    private var _settingsSent:Boolean;
    /** @private 是否已覆盖玩家本地的生命 / 时间设置 */
    private var _settingsApplied:Boolean;
    /** @private 玩家原有的生命比例 */
    private var _origHp:Number;
    /** @private 玩家原有的回合时间 */
    private var _origTime:int;
    /** @private */
    private var _left:Boolean;
    /** @private */
    private var _selectServer:SelectFighterServerLogic;
    /** @private */
    private var _selectClient:SelectFighterClientLogic;
    /** @private */
    private var _relayLogic:LockFrameRelayLogic;
    /** @private */
    private var _serverSync:LanServerSyncCore;
    /** @private */
    private var _clientSync:LanClientSyncCore;
    /** @private */
    private var _delayText:TextField;
    /** @private 是否已开始回合（卡顿仅在此后上报与超时） */
    private var _roundStarted:Boolean;
    /** @private 上次上报 stall 的 <code>getTimer</code> 毫秒 */
    private var _lastStallEmit:int;
    /** @private 本次卡顿是否已上报过 stall */
    private var _stallEmitted:Boolean;
    /** @private 联机前的 <code>GameConfig.FPS_SHINE_EFFECT</code>，会话结束时还原 */
    private var _origShine:int;
    /** @private 是否已覆盖 <code>FPS_SHINE_EFFECT</code> */
    private var _shineOverridden:Boolean;
    /** @private 本端算出的状态哈希环（元素 <code>{epoch, frame, hash, detail}</code>，最旧在前） */
    private var _hashLocal:Array = [];
    /** @private 已收到但本端尚未算到该帧的对端状态哈希环 */
    private var _hashRemote:Array = [];
    /** @private 已核对一致的状态哈希条数 */
    private var _hashVerified:int;
    /** @private 已上报过失同步的 epoch 集合（每个 epoch 只上报一次） */
    private var _hashDesyncEpochs:Object = {};
    /** @private 本场是否检测到过状态哈希失同步 */
    private var _hashDesynced:Boolean;
    /** @private 最近一次中继往返延迟（毫秒） */
    private var _rtt:int;
    /** @private 锁帧渲染回调累计调用次数 */
    private var _renderCount:int;
    /** @private 锁帧渲染回调累计返回 <code>false</code>（本帧等待对端）次数 */
    private var _stallCount:int;

    /**
     * 中继抖动缓冲中等待模拟的帧数（无对战逻辑时为 0），供 FPS 叠层显示。
     * @return 缓冲帧数。
     * @default 0
     */
    public function get bufferedFrames():int {
        return _relayLogic ? _relayLogic.bufferedFrames : 0;
    }

    /**
     * 估算输入到画面的额外滞后（毫秒）：缓冲帧数 × 帧时长 + 中继往返延迟的一半。
     * @return 估算滞后毫秒数。
     * @default 0
     */
    public function get lagMs():int {
        return bufferedFrames * FRAME_MS + (_rtt >> 1);
    }

    /**
     * 已与对端核对一致的状态哈希条数。
     * @return 条数。
     * @default 0
     */
    public function get hashVerified():int {
        return _hashVerified;
    }

    /**
     * 本场是否检测到状态哈希失同步。
     * @return 失同步为 <code>true</code>。
     * @default false
     */
    public function get desynced():Boolean {
        return _hashDesynced;
    }

    /**
     * 锁帧渲染回调累计调用次数（仅对战场景内），供 FPS 叠层按窗口差分计算卡顿占比。
     * @return 累计次数。
     * @default 0
     */
    public function get renderCount():int {
        return _renderCount;
    }

    /**
     * 锁帧渲染回调累计返回 <code>false</code> 的次数（本帧因等待对端输入而不推进逻辑）。
     * @return 累计次数。
     * @default 0
     */
    public function get stallCount():int {
        return _stallCount;
    }

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
     * 联机对局是否已覆盖玩家本地的生命 / 时间设置（此期间不应写存档）。
     * @return 已覆盖且未还原为 <code>true</code>。
     * @default false
     */
    public function get settingsOverridden():Boolean {
        return _settingsApplied;
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

        if (_isHost) {
            _matchHp          = p.hp;
            _matchTime        = p.time;
            _matchDelay       = p.inputDelay;
            _settingsReceived = true;
        }

        _link             = new WebLanLink();
        _link.onHelloOk   = onHelloOk;
        _link.onPeerReady = onPeerReady;
        _link.onPeerLeft  = onPeerLeft;
        _link.onClose     = onLinkClosed;
        _link.onSession   = onSession;
        _link.onTickFrame = onTickFrame;
        _link.onInput     = onSnapshot;
        _link.onRtt       = onRtt;
        _link.onError     = onLinkError;

        WebBridge.registerLeave(leave);
        WebBridge.registerSettings(setSettings);

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

    /**
     * 页面更新房主对局设置（<code>bvnSetSettings</code>）：仅房主且尚未下发 <code>WEB_SETTINGS</code> 时生效，
     * 各字段独立校验，非法字段保留当前值。
     * @param json <code>{"hp":num,"time":int,"inputDelay":int}</code> 的 JSON 字符串，字段可缺省。
     * @example
     * <listing version="3.0">
     * WebSessionCtrl.I.setSettings('{"hp":2,"time":90,"inputDelay":4}');
     * </listing>
     */
    public function setSettings(json:String):void {
        if (!_isHost || _settingsSent || _left) {
            trace('WebSessionCtrl: bvnSetSettings ignored host=' + _isHost + ' sent=' + _settingsSent);
            WebBridge.log('bvnSetSettings ignored');

            return;
        }

        var o:Object;
        try {
            o = JSON.parse(json);
        }
        catch (e:Error) {
            trace('WebSessionCtrl: bvnSetSettings bad json', e);

            return;
        }

        if (!o) {
            return;
        }

        if (WebParams.HP_OPTIONS.indexOf(Number(o.hp)) >= 0) {
            _matchHp = Number(o.hp);
        }
        if (WebParams.TIME_OPTIONS.indexOf(Number(o.time)) >= 0) {
            _matchTime = int(o.time);
        }
        _matchDelay = WebParams.normalizeDelay(o.inputDelay, _matchDelay);
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
        _rtt = rtt;
        WebBridge.emit('ping', {rtt: rtt});
    }

    /** @private 本端算出状态哈希：入环、发给对端，并核对已先到的对端哈希 */
    private function onStateHash(epoch:uint, frame:uint, hash:uint, detail:String):void {
        var entry:Object = {epoch: epoch, frame: frame, hash: hash, detail: detail};
        pushRing(_hashLocal, entry);
        sendSession({type: MSG_HASH, epoch: epoch, frame: frame, hash: hash, detail: detail});

        var remote:Object = takeRing(_hashRemote, epoch, frame);
        if (remote) {
            compareHash(entry, remote);
        }
    }

    /** @private 收到对端状态哈希：本端已算到则立即核对，否则先放入待核对环 */
    private function onRemoteHash(data:Object):void {
        var remote:Object = {epoch: uint(data.epoch), frame: uint(data.frame), hash: uint(data.hash), detail: String(data.detail)};
        var local:Object  = takeRing(_hashLocal, remote.epoch, remote.frame);
        if (local) {
            compareHash(local, remote);
        }
        else {
            pushRing(_hashRemote, remote);
        }
    }

    /** @private 核对同一 (epoch, frame) 的两端哈希；不一致时每个 epoch 只上报一次 */
    private function compareHash(local:Object, remote:Object):void {
        if (local.hash == remote.hash) {
            _hashVerified++;

            return;
        }

        _hashDesynced     = true;
        if (_hashDesyncEpochs[local.epoch]) {
            return;
        }

        _hashDesyncEpochs[local.epoch] = true;

        var msg:String = 'desync epoch=' + local.epoch + ' frame=' + local.frame + ' local[' + local.detail + '] remote[' + remote.detail + ']';
        trace(msg);
        WebBridge.log(msg);
        WebBridge.emit('desync', {frame: local.frame, epoch: local.epoch, local: local.detail, remote: remote.detail});
    }

    /** @private 入环并保持最多 <code>HASH_RING</code> 条 */
    private function pushRing(ring:Array, entry:Object):void {
        ring.push(entry);
        while (ring.length > HASH_RING) {
            ring.shift();
        }
    }

    /** @private 取出并移除环中 (epoch, frame) 对应条目，没有返回 <code>null</code> */
    private function takeRing(ring:Array, epoch:uint, frame:uint):Object {
        for (var i:int = ring.length - 1; i >= 0; i--) {
            var e:Object = ring[i];
            if (e.epoch == epoch && e.frame == frame) {
                ring.splice(i, 1);

                return e;
            }
        }

        return null;
    }

    /** @private 会话消息：状态哈希与就绪握手优先，其余交给选人 / 同步逻辑 */
    private function onSession(data:Object):void {
        if (data && data.type == MSG_HASH) {
            onRemoteHash(data);

            return;
        }

        if (data && data.type == MSG_READY) {
            _remoteReady = true;
            tryStart();

            return;
        }

        if (data && data.type == MSG_SETTINGS) {
            if (!_isHost && !_settingsReceived) {
                _matchHp          = WebParams.normalizeHp(data.hp);
                _matchTime        = WebParams.normalizeTime(data.time);
                _matchDelay       = WebParams.normalizeDelay(data.inputDelay, _matchDelay);
                _settingsReceived = true;
                tryStart();
            }

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

    /** @private 中继节拍帧：两端对称交给锁帧逻辑 */
    /** @private 客户端：房主位置快照（INPUT 帧，type 2）交给中继锁帧逻辑按帧号延后应用 */
    private function onSnapshot(bytes:ByteArray):void {
        if (!_isHost && _relayLogic) {
            _relayLogic.receiveSyncUpdate(bytes);
        }
    }

    /** @private */
    private function onTickFrame(payload:ByteArray):void {
        if (_relayLogic) {
            _relayLogic.receiveTickFrame(payload);
        }
    }

    /** @private 本机资源与对手席位都就绪后发出就绪握手 */
    private function tryReady():void {
        if (_localReady || !_gameLoaded || !_peerReady || _left) {
            return;
        }

        _localReady = true;

        if (_isHost) {
            _settingsSent = true;
            sendSession({type: MSG_SETTINGS, hp: _matchHp, time: _matchTime, inputDelay: _matchDelay});
        }

        sendSession({type: MSG_READY});
        tryStart();
    }

    /** @private 双方都就绪才开始 */
    private function tryStart():void {
        if (_localReady && _remoteReady && _settingsReceived && !_matchStarted && !_left) {
            startMatch();
        }
    }

    /** @private */
    private function startMatch():void {
        _matchStarted = true;
        active        = true;

        // 全屏闪光只影响画面，不参与逻辑；联机期间双方一律关闭以减轻渲染
        _origShine       = GameConfig.FPS_SHINE_EFFECT;
        _shineOverridden = true;
        GameConfig.FPS_SHINE_EFFECT = 0;

        GameEvent.addEventListener(GameEvent.GAME_START, onGameStart);
        GameEvent.addEventListener(GameEvent.GAME_END, onGameEnd);
        GameEvent.addEventListener(GameEvent.ENTER_STAGE, onEnterStage);
        GameEvent.addEventListener(GameEvent.ROUND_START, onRoundStart);

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

        applySettings(true);

        MainGame.I.goSelect();
    }

    /**
     * @private 保存玩家原设置（仅首次）并套用会话的生命 / 时间；每场对局进入选人 / 对战前都会重新调用，
     * 防止被其他流程改回；<code>emit</code> 为 <code>true</code> 时上报 <code>matchSettings</code>
     */
    private function applySettings(emit:Boolean):void {
        var cfg:ConfigVO = GameData.I.config;

        if (!_settingsApplied) {
            _origHp          = cfg.fighterHP;
            _origTime        = cfg.fightTime;
            _settingsApplied = true;
        }

        cfg.fighterHP = _matchHp;
        cfg.fightTime = _matchTime;

        if (_isHost) {
            LanNetConfig.inputDelay = _matchDelay;
        }

        if (emit) {
            WebBridge.emit('matchSettings', {hp: _matchHp, time: _matchTime, inputDelay: _matchDelay});
        }
    }

    /** @private 还原玩家原有的生命 / 时间设置 */
    private function restoreSettings():void {
        if (!_settingsApplied) {
            return;
        }

        _settingsApplied = false;

        GameData.I.config.fighterHP = _origHp;
        GameData.I.config.fightTime = _origTime;
    }

    /** @private 房主：对齐 LANServerCtrl.gameStart */
    private function startHost():void {
        // 两端对称由中继节拍驱动，不再使用房主节拍
        LanNetConfig.relayPaced = true;
        LanNetConfig.hostPaced  = false;
        GameInterface.instance.updateInputConfig();
        LockFrameLogic.I.initServer(renderRelay);
        LanNetConfig.inputDelay = _matchDelay;
        LANUtils.updateParams();

        _selectServer = new SelectFighterServerLogic();
        _selectServer.init(sendSession);

        createRelayLogic();
        _relayLogic.snapshotSender = sendSnapshot;

        LanGameMenuCtrl.I.init(createExitDialog());

        _serverSync ||= new LanServerSyncCore();
        _serverSync.bind(_relayLogic, sendSession);
    }

    /** @private 客户端：对齐 LANClientCtrl.gameStart */
    private function startClient():void {
        // 与房主一致：客户端同样由中继节拍驱动
        LanNetConfig.relayPaced = true;
        LanNetConfig.hostPaced  = false;
        _delayText                   = new TextField();
        _delayText.text              = '0ms';
        var tf:TextFormat            = new TextFormat();
        tf.color                     = 0xffffff;
        tf.size                      = 16;
        _delayText.defaultTextFormat = tf;
        MainGame.I.stage.addChild(_delayText);

        _selectClient = new SelectFighterClientLogic();
        _selectClient.init(sendSession);

        createRelayLogic();

        _clientSync ||= new LanClientSyncCore(100);
        _clientSync.bind(_relayLogic, onSyncFatalError, _delayText);
        _clientSync.onDesync = onDesync;
        _link.syncCore = _clientSync;
        _relayLogic.syncCore = _clientSync;

        GameCtrl.I.autoEndRoundAble    = false;
        GameCtrl.I.autoStartAble       = false;
        SelectFighterStage.AUTO_FINISH = false;
        LoadingStage.AUTO_START_GAME   = false;

        GameInterface.instance.updateInputConfig();

        LockFrameLogic.I.initClient(renderRelay);

        LanGameMenuCtrl.I.init(createExitDialog());

        LANUtils.updateParams();
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

    /** @private 房主：经 INPUT 帧（type 2）把位置快照发给客户端 */
    private function sendSnapshot(snap:ByteArray):void {
        if (_link) {
            _link.sendUDP(snap);
        }
    }

    /** @private 创建两端对称的中继节拍锁帧逻辑并绑定卡顿回调 */
    private function createRelayLogic():void {
        _hashLocal        = [];
        _hashRemote       = [];
        _hashVerified     = 0;
        _hashDesyncEpochs = {};
        _hashDesynced     = false;

        _relayLogic = new LockFrameRelayLogic();
        _relayLogic.onStateHash = onStateHash;
        _relayLogic.init(
            _link,
            _isHost ? InputManager.I.socket_input_p1 : InputManager.I.socket_input_p2,
            InputManager.I.socket_input_p1,
            InputManager.I.socket_input_p2,
            _isHost
        );
        bindStall(_relayLogic.stallMonitor);
    }

    /** @private 两端共用的锁帧渲染回调：对战场景走中继节拍，其余场景本侧输入空转 */
    private function renderRelay():Boolean {
        if (_relayLogic && MainGame.stageCtrl.currentStage is GameStage) {
            var ok:Boolean = _relayLogic.render();
            countRender(ok);

            return ok;
        }

        if (_isHost) {
            InputManager.I.socket_input_p1.freeRender();
        }
        else {
            InputManager.I.socket_input_p2.freeRender();
        }

        return true;
    }

    /** @private 累计渲染回调与卡顿帧数 */
    private function countRender(ok:Boolean):void {
        _renderCount++;

        if (!ok) {
            _stallCount++;
        }
    }

    /** @private */
    private function onSyncFatalError():void {
        finish('sync_error');
        alertGame('alert.lan_client_ctrl.disconnect_title', 'alert.lan_client_ctrl.disconnect_error');
    }

    /** @private 注册卡顿回调（房主与客户端共用） */
    private function bindStall(monitor:LanStallMonitor):void {
        monitor.onStall   = onStall;
        monitor.onResume  = onResume;
        monitor.onTimeout = onStallTimeout;
    }

    /** @private 卡顿预警：回合开始后才上报，最多每 250ms 一次 */
    private function onStall(ms:int):void {
        if (!_roundStarted || _left) {
            return;
        }

        var now:int = getTimer();
        if (_stallEmitted && now - _lastStallEmit < STALL_EMIT_MS) {
            return;
        }

        _stallEmitted  = true;
        _lastStallEmit = now;
        WebBridge.emit('stall', {ms: ms});
    }

    /** @private 卡顿恢复 */
    private function onResume(ms:int):void {
        if (!_stallEmitted) {
            return;
        }

        _stallEmitted = false;

        if (!_left) {
            WebBridge.emit('resume', {ms: ms});
        }
    }

    /** @private 卡顿超时：回合开始后才放弃对局 */
    private function onStallTimeout(ms:int):void {
        if (!_roundStarted || _left) {
            return;
        }

        finish('stall_timeout');
        alertGame('alert.lan_client_ctrl.disconnect_title', 'alert.lan_client_ctrl.connection_interrupt');
    }

    /** @private 失同步：仅上报并记录，不中断对局 */
    private function onDesync(round:int, localP1:Number, remoteP1:Number, localP2:Number, remoteP2:Number):void {
        trace('WebSessionCtrl: desync round=' + round
                + ' p1=' + localP1 + '/' + remoteP1
                + ' p2=' + localP2 + '/' + remoteP2);
        WebBridge.emit('desync', {round: round, p1: [localP1, remoteP1], p2: [localP2, remoteP2]});
    }

    /** @private */
    private function onRoundStart(e:GameEvent):void {
        _roundStarted = true;

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

        _matchEnded   = true;
        _roundStarted = false;

        var team:Object = GameCtrl.I.gameRunData.lastWinnerTeam;
        if (team && team.id == TeamID.TEAM_1) {
            WebBridge.emit('matchEnd', {winner: WebParams.ROLE_HOST});
        }
        else if (team && team.id == TeamID.TEAM_2) {
            WebBridge.emit('matchEnd', {winner: WebParams.ROLE_CLIENT});
        }
        else {
            WebBridge.emit('matchEnd', {});
        }
    }

    /** @private 进入选人 / 加载 / 对战场景时重新套用会话设置；会话中途回到主菜单视为离开 */
    private function onEnterStage(e:GameEvent):void {
        if (!active) {
            return;
        }

        if (e.param == SelectFighterStage || e.param == LoadingStage || e.param == GameStage) {
            applySettings(false);
        }
        else if (e.param == MenuStage) {
            finish('leave');
        }
    }

    /** @private 结束会话：释放对战资源、还原玩家本地设置、关闭连接并显示等待界面；<code>notify</code> 为 <code>false</code> 时不发 <code>disconnected</code> */
    private function finish(reason:String, notify:Boolean = true):void {
        if (_left) {
            return;
        }

        _left = true;

        disposeMatch();

        if (_link) {
            _link.close();
            _link = null;
        }

        if (notify) {
            WebBridge.emit('disconnected', {reason: reason});
        }

        refreshWait();
    }

    /** @private 释放选人 / 锁帧 / 同步逻辑，还原输入与游戏流程开关 */
    private function disposeMatch():void {
        GameEvent.removeEventListener(GameEvent.GAME_START, onGameStart);
        GameEvent.removeEventListener(GameEvent.GAME_END, onGameEnd);
        GameEvent.removeEventListener(GameEvent.ENTER_STAGE, onEnterStage);
        GameEvent.removeEventListener(GameEvent.ROUND_START, onRoundStart);

        LanNetConfig.relayPaced = false;
        LanNetConfig.hostPaced  = false;
        _roundStarted = false;
        _stallEmitted = false;

        restoreSettings();

        if (!_matchStarted) {
            return;
        }

        active = false;

        if (_shineOverridden) {
            _shineOverridden            = false;
            GameConfig.FPS_SHINE_EFFECT = _origShine;
        }

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

        if (_relayLogic) {
            _relayLogic.dispose();
            _relayLogic = null;
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
