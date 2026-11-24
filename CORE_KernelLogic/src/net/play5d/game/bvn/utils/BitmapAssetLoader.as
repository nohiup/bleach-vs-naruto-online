/*
 * Copyright (C) 2021-2024, 5DPLAY Game Studio
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

package net.play5d.game.bvn.utils {
import flash.display.Bitmap;
import flash.display.BitmapData;
import flash.display.DisplayObject;

import net.play5d.game.bvn.ctrler.AssetManager;

public class BitmapAssetLoader {

    /**
     * 同时在途的最大加载数。
     *
     * @default 12
     */
    public static var MAX_CONCURRENT:int = 12;

    private var _cacheObj:Object = {};
    private var _progressBack:Function;

    public function getBitmap(id:String):Bitmap {
//			var r:DisplayObject = _cacheObj[id];
//
//			if(r == null) return null;
//
//			if(r is BitmapData){
//				return new Bitmap(r as BitmapData);
//			}

        var bd:BitmapData = _cacheObj[id];
        if (bd == null) {
            return null;
        }
        return new Bitmap(bd);
    }

    /**
     * 批量加载位图并缓存；以有界并发加载，全部结束（成功或失败）后调用一次 <code>success</code>。
     *
     * <p>同时最多 <code>MAX_CONCURRENT</code> 个请求在途，用于隐藏网络往返延迟；
     * 每个 URL 独立缓存，结果与完成顺序无关。</p>
     *
     * @param urls 位图 URL 数组。
     * @param success 全部结束回调，签名为 <code>function():void</code>；可为 <code>null</code>。
     * @param progress 总进度回调，签名为 <code>function(p:Number):void</code>（<code>p</code> 为 0–1）；可为 <code>null</code>。
     * @example
     * <listing version="3.0">
     * loader.loadQueue(['a.png', 'b.png'], onDone, onProgress);
     * </listing>
     */
    public function loadQueue(urls:Array, success:Function, progress:Function = null):void {
        // 每次队列使用独立状态，避免重入时互相覆盖
        var pending:Array    = urls.concat();
        var total:int        = pending.length;
        var done:int         = 0;
        var running:int      = 0;
        var finished:Boolean = false;
        var partial:Object   = {};
        var seq:int          = 0;
        var pumping:Boolean  = false;
        var again:Boolean    = false;

        _progressBack = progress;

        if (total < 1) {
            finish();
            return;
        }

        pump();

        function pump():void {
            // 回调可能同步触发，用标记避免递归展开
            if (pumping) {
                again = true;
                return;
            }
            pumping = true;
            do {
                again = false;
                while (!finished && running < MAX_CONCURRENT && pending.length > 0) {
                    startOne(pending.shift());
                }
            }
            while (again);
            pumping = false;
            if (!finished && done >= total) {
                finish();
            }
        }

        function startOne(url:String):void {
            var id:int       = seq++;
            var over:Boolean = false;

            running++;
            load(url, onOver, onItemProgress);

            function onItemProgress(v:Number):void {
                if (over) {
                    return;
                }
                partial[id] = v > 1 ? 1 : v;
                report();
            }

            function onOver():void {
                if (over) {
                    return;
                }
                over = true;
                delete partial[id];
                running--;
                done++;
                report();
                pump();
            }
        }

        function report():void {
            if (finished || _progressBack == null) {
                return;
            }
            var cur:Number = done;
            for each(var v:Number in partial) {
                cur += v;
            }
            var p:Number = cur / total;
            _progressBack(p > 1 ? 1 : p);
        }

        function finish():void {
            if (finished) {
                return;
            }
            finished      = true;
            _progressBack = null;
            if (success != null) {
                success();
            }
        }
    }

    private function load(url:String, back:Function = null, progress:Function = null):void {
        AssetManager.I.loadBitmap(url, loadCom, loadFail, progress);

        function loadCom(bp:DisplayObject):void {
            cacheBitmap(url, bp);
            if (back != null) {
                back();
            }
        }

        function loadFail():void {
            trace('BitmapAssetLoader.loadFail ::', url);
            if (back != null) {
                back();
            }
        }

    }

    private function cacheBitmap(id:String, bp:DisplayObject):void {
        var content:Bitmap = bp as Bitmap;

        if (!content) {
            trace('BitmapAssetLoader.cacheBitmap Error');
            return;
        }

        var cache:BitmapData;

        if (content) {
            try {
                cache = content.bitmapData;
            }
            catch (e:Error) {
                trace('BitmapAssetLoader.cacheBitmap::', e);
//					cache = content;
            }
        }
        else {
//				cache = loader;
        }

        if (cache) {
            _cacheObj[id] = cache;
        }

        AssetManager.I.disposeAsset(id);

    }

}
}
