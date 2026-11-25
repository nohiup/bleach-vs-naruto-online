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
import net.play5d.game.bvn.data.vos.GameRunDataVO;
import net.play5d.game.bvn.fighter.Assister;
import net.play5d.game.bvn.fighter.FighterMC;
import net.play5d.game.bvn.fighter.FighterMain;

/**
 * 中继定帧失步检测：对确定性战斗状态计算 FNV-1a 32 位哈希。
 *
 * <p>只读取状态，不修改；每秒调用一次即可。浮点量按 ×10 取整后参与哈希，以便发现小数位漂移。</p>
 *
 * @see LockFrameRelayLogic
 */
public class LanStateHash {

    /** @private FNV-1a 偏移基数 */
    private static const FNV_OFFSET:uint = 0x811C9DC5;

    /** @private 当前累计哈希 */
    private static var _h:uint;
    /** @private 当前明细 */
    private static var _detail:String = '';

    /**
     * 计算当前战斗状态哈希。
     *
     * @param runData 对局运行数据。
     * @return 哈希值；明细经 <code>detail</code> 读取。
     */
    public static function compute(runData:GameRunDataVO):uint {
        _h      = FNV_OFFSET;
        _detail = '';
        if (!runData) {
            return _h;
        }

        add(runData.round);
        add(runData.gameTime);
        add(runData.p1Wins);
        add(runData.p2Wins);

        _detail = 'r=' + runData.round + ' t=' + runData.gameTime + ' | ';

        hashFighter('p1', runData.p1FighterGroup.currentFighter, runData.p1FighterGroup.currentAssister);
        hashFighter('p2', runData.p2FighterGroup.currentFighter, runData.p2FighterGroup.currentAssister);

        return _h;
    }

    /**
     * 最近一次 <code>compute</code> 的明细，如 <code>r=1 t=90 | p1 x=123 y=0 hp=4000 ... | p2 ...</code>。
     */
    public static function get detail():String {
        return _detail;
    }

    /** @private */
    private static function hashFighter(tag:String, f:FighterMain, a:Assister):void {
        if (!f) {
            _detail += tag + ' none | ';

            return;
        }

        var mc:FighterMC = f.getMC();
        var frame:int    = mc ? mc.getCurrentFrame() : -1;
        var fcnt:int     = mc ? mc.getCurrentFrameCount() : -1;
        var label:String = mc ? mc.currentFrameName : null;
        var x:int        = Math.round(f.x * 10);
        var y:int        = Math.round(f.y * 10);
        var hp:int       = Math.round(f.hp * 10);
        var qi:int       = Math.round(f.qi * 10);
        var en:int       = Math.round(f.energy * 10);
        var fz:int       = Math.round(f.fzqi * 10);
        var vx:int       = Math.round(f.getVecX() * 10);
        var vy:int       = Math.round(f.getVecY() * 10);
        var flags:int    = (f.isAlive ? 1 : 0)
                | (f.isInAir ? 2 : 0)
                | (f.isSteelBody ? 4 : 0)
                | (f.isSuperSteelBody ? 8 : 0)
                | (f.energyOverLoad ? 16 : 0)
                | (f.isAllowBeHit ? 32 : 0)
                | (f.hurtHit ? 64 : 0)
                | (f.defenseHit ? 128 : 0)
                | (a && a.isAttacking ? 256 : 0);

        add(x);
        add(y);
        add(hp);
        add(qi);
        add(en);
        add(fz);
        add(vx);
        add(vy);
        add(f.direct);
        add(f.actionState);
        add(frame);
        add(fcnt);
        add(flags);
        addStr(label);
        if (a) {
            add(Math.round(a.x * 10));
            add(Math.round(a.y * 10));
        }

        _detail += tag + ' x=' + (x / 10) + ' y=' + (y / 10) + ' hp=' + (hp / 10) + ' qi=' + (qi / 10)
                + ' en=' + (en / 10) + ' dir=' + f.direct + ' act=' + f.actionState
                + ' f=' + frame + '/' + fcnt + ' lbl=' + label + ' fl=' + flags + ' | ';
    }

    /** @private 按字节喂入 FNV-1a */
    private static function add(v:int):void {
        mix(v & 0xFF);
        mix((v >> 8) & 0xFF);
        mix((v >> 16) & 0xFF);
        mix((v >> 24) & 0xFF);
    }

    /** @private h = (h ^ b) * 16777619 mod 2^32，乘法拆成 (h<<24) + h*0x193 以免丢精度 */
    private static function mix(b:int):void {
        var t:uint = _h ^ b;
        _h         = (t << 24) + t * 0x193;
    }

    /** @private */
    private static function addStr(s:String):void {
        if (!s) {
            add(0);

            return;
        }

        var n:int = s.length;
        for (var i:int = 0; i < n; i++) {
            add(s.charCodeAt(i));
        }
    }
}
}
