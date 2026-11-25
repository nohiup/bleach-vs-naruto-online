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

package net.play5d.game.bvn.map {
import flash.display.DisplayObject;
import flash.display.DisplayObjectContainer;
import flash.display.MovieClip;
import flash.geom.Matrix;
import flash.geom.Rectangle;

/**
 * 对局地图层位图缓存工具。
 *
 * <p>在构建对局后为地图主层启用 <code>cacheAsBitmapMatrix</code> /
 * <code>cacheAsBitmap</code>，供各壳 <code>afterBuildGame</code> 复用。</p>
 *
 * @see MapMain
 */
public class MapLayerCacheUtil {

    /**
     * 网页壳静态层缓存总开关（默认开启），关闭后 <code>enableStaticBitmapCache</code> 不做任何事，便于 A/B 对比。
     */
    public static var webStaticCacheEnabled:Boolean = true;

    /** @private 位图缓存单边像素上限（Flash 位图上限 8191） */
    private static const CACHE_MAX_SIZE:Number = 8191;

    /** @private 动画检测递归深度上限 */
    private static const SCAN_MAX_DEPTH:int = 8;

    /**
     * 为地图各层启用位图缓存。
     *
     * @param map 当前对局地图；为 null 时忽略。
     *
     * @example
     * <listing version="3.0">
     * MapLayerCacheUtil.enableBitmapCache(GameCtrl.I.gameState.getMap());
     * </listing>
     */
    public static function enableBitmapCache(map:MapMain):void {
        if (!map) {
            return;
        }
        if (map.mapLayer) {
            map.mapLayer.cacheAsBitmapMatrix = new Matrix();
        }
        if (map.frontLayer) {
            map.frontLayer.cacheAsBitmapMatrix = new Matrix();
        }
        if (map.frontFixLayer) {
            map.frontFixLayer.cacheAsBitmapMatrix = new Matrix();
        }
        if (map.bgLayer) {
            map.bgLayer.cacheAsBitmap = true;
        }
    }

    /**
     * 为地图静态层启用纯 <code>cacheAsBitmap</code>（不使用 AIR 专有 API，可在 Flash Player / Ruffle 运行）。
     *
     * <p>仅缓存 <code>mapLayer</code> 与 <code>bgLayer</code>，且要求层内无多帧 MovieClip、尺寸不超过位图上限。
     * <code>frontLayer</code> / <code>frontFixLayer</code> 每隔数帧由 <code>renderOptical</code> 改写子项透明度，
     * 会使缓存反复失效，故不缓存。镜头平移不会使缓存失效；镜头缩放（<code>GameCamera</code> 缩放整个对局容器）
     * 变化期间会重新栅格化，缩放稳定后恢复命中。</p>
     *
     * @param map 当前对局地图；为 null 或开关关闭时忽略。
     */
    public static function enableStaticBitmapCache(map:MapMain):void {
        if (!webStaticCacheEnabled || !map) {
            return;
        }
        cacheIfStatic(map.mapLayer);
        cacheIfStatic(map.bgLayer);
    }

    /**
     * @private 层可用、静态且尺寸合规时开启缓存。
     */
    private static function cacheIfStatic(layer:MapLayer):void {
        if (!layer || !layer.enabled) {
            return;
        }
        try {
            var b:Rectangle = layer.getBounds(layer);
            if (b.width <= 0 || b.height <= 0 || b.width > CACHE_MAX_SIZE || b.height > CACHE_MAX_SIZE) {
                return;
            }
            if (hasAnimation(layer, 0)) {
                return;
            }
            layer.cacheAsBitmap = true;
        }
        catch (e:Error) {
            trace('MapLayerCacheUtil.cacheIfStatic error ::', e);
        }
    }

    /**
     * @private 递归检测是否含多帧 MovieClip（保守视为动画）。
     */
    private static function hasAnimation(d:DisplayObject, depth:int):Boolean {
        var mc:MovieClip = d as MovieClip;
        if (mc && mc.totalFrames > 1) {
            return true;
        }
        var c:DisplayObjectContainer = d as DisplayObjectContainer;
        if (!c) {
            return false;
        }
        if (depth >= SCAN_MAX_DEPTH) {
            return c.numChildren > 0;
        }
        for (var i:int = 0; i < c.numChildren; i++) {
            if (hasAnimation(c.getChildAt(i), depth + 1)) {
                return true;
            }
        }
        return false;
    }
}
}
