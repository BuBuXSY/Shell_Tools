// ==UserScript==
// @name              Mactype助手增强版 (Edge优化)
// @version           1.0.0
// @description       专为Microsoft Edge优化的Windows字体渲染增强工具，支持多种渲染方式、自定义字体、预设方案等高级功能
// @author            BuBuXSY
// @license           MIT
// @compatible        edge Microsoft Edge 完全兼容
// @compatible        chrome 谷歌浏览器完全兼容
// @require           https://unpkg.com/sweetalert2@10.16.6/dist/sweetalert2.min.js
// @resource          swalStyle https://unpkg.com/sweetalert2@10.16.6/dist/sweetalert2.min.css
// @match             *://*/*
// @exclude           *://www.office.com/*
// @exclude           *://outlook.live.com/*
// @exclude           *://onedrive.live.com/*
// @run-at            document-start
// @grant             GM_getValue
// @grant             GM_setValue
// @grant             GM_registerMenuCommand
// @grant             GM_getResourceText
// @grant             GM_info
// @icon              data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxMjggMTI4Ij48cGF0aCBkPSJNMTIwIDcuMWM0LjQgMCA4IDQuMSA4IDl2NzMuMmMwIDUtMy42IDktOCA5SDgwLjhsNy4yIDE2LjNjLjggMi4zIDAgNS0xLjYgNS45LS40LjUtMS4yLjUtMS42LjVINDMuNmMtMi40IDAtNC0xLjgtNC00LjUgMC0uOSAwLTEuNC40LTEuOGw3LjItMTYuM0g4Yy00LjQgMC04LTQuMS04LTlWMTYuMWMwLTUgMy42LTkgOC05aDExMnoiIGZpbGw9IiM0NDQiLz48cGF0aCBkPSJNMTAyLjMgMzQuN2ExNC4yOCAxNC4yOCAwIDAgMC02LjItNi4yYy0yLjctMS40LTUuMy0yLjItMTIuNi0yLjJINjkuMXY1NC42aDE0LjRjNy4zIDAgOS45LS44IDEyLjYtMi4yYTE1LjQyIDE1LjQyIDAgMCAwIDYuMi02LjJjMS40LTIuNyAyLjItNS4zIDIuMi0xMi42VjQ3LjNjMC03LjMtLjgtOS45LTIuMi0xMi42em0tOC43IDI4LjJjMCAyLjQtLjIgMy4zLS43IDQuMnMtMS4yIDEuNi0yLjEgMi4xYy0uOS40LTEuOC43LTQuMi43SDgwVjM3LjJoNi42YzIuNCAwIDMuMy4yIDQuMi43czEuNiAxLjIgMi4xIDIuMWMuNC45LjcgMS44LjcgNC4ydjE4Ljd6TTUwIDQ4LjFIMzYuM1YyNi4zSDI1LjR2NTQuNWgxMC45VjU5SDUwdjIxLjhoMTAuOVYyNi4zSDUwdjIxLjh6IiBmaWxsPSIjZmZmIi8+PC9zdmc+
// ==/UserScript==

(function () {
    'use strict';

    // 字体配置 - 针对Edge优化
    const FONT_CONFIG = {
        sans: '"更纱黑体 UI SC", "NotoSansM Nerd Font Mono", "Noto Sans CJK SC", "Microsoft YaHei UI", "Segoe UI Variable", "Segoe UI", system-ui, -apple-system, sans-serif',
        serif: '"Noto Serif SC", "Source Han Serif SC", "思源宋体", "STSong", "Georgia", serif',
        mono: '"文泉驿等宽微米黑", "WenQuanYi Micro Hei Mono", "Sarasa Term SC", "Cascadia Code", "Cascadia Mono", "Consolas", monospace'
    };

    // Edge特定配置
    const EDGE_CONFIG = {
        // 检测是否为Edge浏览器
        isEdge: /Edg/.test(navigator.userAgent),
        // Edge版本
        edgeVersion: navigator.userAgent.match(/Edg\/(\d+)/)?.[1] || 0,
        // 是否支持DirectWrite
        supportsDirectWrite: true,
        // 是否为高DPI屏幕
        isHighDPI: window.devicePixelRatio > 1
    };

    // 预设方案 - Edge优化
    const PRESETS = {
        light: {
            name: '轻度优化',
            stroke: EDGE_CONFIG.isHighDPI ? 0.1 : 0.15,
            shadow: '0 0.5px 1px rgba(0,0,0,0.08)',
            smooth: 'antialiased',
            fontAdjust: true
        },
        balanced: {
            name: '平衡模式',
            stroke: EDGE_CONFIG.isHighDPI ? 0.25 : 0.3,
            shadow: '0 1px 2px rgba(0,0,0,0.1)',
            smooth: 'antialiased',
            fontAdjust: true
        },
        clear: {
            name: '清晰模式',
            stroke: EDGE_CONFIG.isHighDPI ? 0.4 : 0.45,
            shadow: '0 1px 3px rgba(0,0,0,0.12)',
            smooth: 'antialiased',
            fontAdjust: true
        },
        strong: {
            name: '加强模式',
            stroke: EDGE_CONFIG.isHighDPI ? 0.55 : 0.6,
            shadow: '0 2px 4px rgba(0,0,0,0.15)',
            smooth: 'subpixel-antialiased',
            fontAdjust: true
        },
        edge: {
            name: 'Edge专属',
            stroke: EDGE_CONFIG.isHighDPI ? 0.35 : 0.4,
            shadow: '0 1px 2.5px rgba(0,0,0,0.11)',
            smooth: 'antialiased',
            fontAdjust: true
        },
        custom: {
            name: '自定义',
            stroke: 0,
            shadow: 'none',
            smooth: 'antialiased',
            fontAdjust: true
        }
    };

    let util = {
        getValue(name, defaultValue) {
            const value = GM_getValue(name);
            return value !== undefined ? value : defaultValue;
        },

        setValue(name, value) {
            GM_setValue(name, value);
        },

        addStyle(id, tag, css) {
            tag = tag || 'style';
            let doc = document, styleDom = doc.getElementById(id);
            if (styleDom) styleDom.innerHTML = css;
            else {
                let style = doc.createElement(tag);
                style.rel = 'stylesheet';
                style.id = id;
                tag === 'style' ? style.innerHTML = css : style.href = css;
                document.head.appendChild(style);
            }
        },

        removeElementById(eleId) {
            let ele = document.getElementById(eleId);
            ele && ele.parentNode.removeChild(ele);
        }
    };

    let main = {
        config: {
            currentPreset: 'balanced',
            currentStroke: 0.3,
            currentShadow: '0 1px 2px rgba(0,0,0,0.1)',
            currentSmooth: 'antialiased',
            enableFontReplace: true,
            enableShadow: true,
            enableSmooth: true,
            enableLetterSpacing: true,
            letterSpacing: 0.02,
            lineHeight: 1.6,
            whiteList: [],
            blackList: [],
            customFonts: false
        },

        /**
         * 初始化配置
         */
        initValue() {
            const savedConfig = util.getValue('enhanced_config', null);
            if (savedConfig) {
                this.config = {...this.config, ...savedConfig};
            } else {
                util.setValue('enhanced_config', this.config);
            }

            // 兼容旧版本
            const oldVal = util.getValue('current_val');
            if (oldVal !== undefined && !savedConfig) {
                this.config.currentStroke = oldVal;
                this.config.currentPreset = 'custom';
                this.saveConfig();
            }
        },

        saveConfig() {
            util.setValue('enhanced_config', this.config);
        },

        showSetting() {
            const currentPreset = PRESETS[this.config.currentPreset];
            const browserInfo = EDGE_CONFIG.isEdge ?
                `<div style="text-align: center; color: #0078d4; margin-bottom: 10px;">
                    🌐 Microsoft Edge ${EDGE_CONFIG.edgeVersion} |
                    ${EDGE_CONFIG.isHighDPI ? '高DPI模式' : '标准模式'} |
                    像素比: ${window.devicePixelRatio}
                </div>` : '';

            Swal.fire({
                title: '字体渲染增强设置',
                html: `
                    ${browserInfo}
                    <style>
                        .setting-group { margin: 15px 0; text-align: left; }
                        .setting-label { display: block; margin-bottom: 5px; font-weight: bold; }
                        .setting-item { margin: 10px 0; }
                        .preset-buttons { display: flex; gap: 10px; flex-wrap: wrap; justify-content: center; margin: 10px 0; }
                        .preset-btn { padding: 8px 16px; border: 2px solid #ddd; background: white; border-radius: 6px; cursor: pointer; transition: all 0.3s; }
                        .preset-btn:hover { border-color: #338fff; }
                        .preset-btn.active { background: #338fff; color: white; border-color: #338fff; }
                        .preset-btn.edge-special { background: linear-gradient(45deg, #0078d4, #40e0d0); color: white; border: none; }
                        .preset-btn.edge-special:hover { transform: scale(1.05); }
                        .switch { position: relative; display: inline-block; width: 50px; height: 24px; }
                        .switch input { opacity: 0; width: 0; height: 0; }
                        .slider { position: absolute; cursor: pointer; top: 0; left: 0; right: 0; bottom: 0; background-color: #ccc; transition: .4s; border-radius: 24px; }
                        .slider:before { position: absolute; content: ""; height: 18px; width: 18px; left: 3px; bottom: 3px; background-color: white; transition: .4s; border-radius: 50%; }
                        input:checked + .slider { background-color: #338fff; }
                        input:checked + .slider:before { transform: translateX(26px); }
                        .range-value { display: inline-block; width: 60px; text-align: center; }
                    </style>

                    <div class="setting-group">
                        <label class="setting-label">预设方案</label>
                        <div class="preset-buttons">
                            ${Object.entries(PRESETS).map(([key, preset]) => `
                                <button class="preset-btn ${key === this.config.currentPreset ? 'active' : ''} ${key === 'edge' ? 'edge-special' : ''}" data-preset="${key}">
                                    ${preset.name} ${key === 'edge' ? '⭐' : ''}
                                </button>
                            `).join('')}
                        </div>
                    </div>

                    <div class="setting-group">
                        <label class="setting-label">描边强度: <span class="range-value" id="stroke-value">${this.config.currentStroke}</span></label>
                        <input type="range" id="stroke-range" min="0" max="1" step="0.05" value="${this.config.currentStroke}" style="width: 100%">
                    </div>

                    <div class="setting-group">
                        <div class="setting-item">
                            <label>
                                <span>启用文字阴影</span>
                                <label class="switch">
                                    <input type="checkbox" id="enable-shadow" ${this.config.enableShadow ? 'checked' : ''}>
                                    <span class="slider"></span>
                                </label>
                            </label>
                        </div>

                        <div class="setting-item">
                            <label>
                                <span>字体平滑</span>
                                <label class="switch">
                                    <input type="checkbox" id="enable-smooth" ${this.config.enableSmooth ? 'checked' : ''}>
                                    <span class="slider"></span>
                                </label>
                            </label>
                        </div>

                        <div class="setting-item">
                            <label>
                                <span>优化字间距</span>
                                <label class="switch">
                                    <input type="checkbox" id="enable-spacing" ${this.config.enableLetterSpacing ? 'checked' : ''}>
                                    <span class="slider"></span>
                                </label>
                            </label>
                        </div>

                        <div class="setting-item">
                            <label>
                                <span>使用自定义字体</span>
                                <label class="switch">
                                    <input type="checkbox" id="custom-fonts" ${this.config.customFonts ? 'checked' : ''}>
                                    <span class="slider"></span>
                                </label>
                            </label>
                        </div>
                    </div>

                    <div class="setting-group">
                        <label class="setting-label">字间距: <span class="range-value" id="spacing-value">${this.config.letterSpacing}em</span></label>
                        <input type="range" id="spacing-range" min="-0.05" max="0.1" step="0.01" value="${this.config.letterSpacing}" style="width: 100%">
                    </div>

                    <div class="setting-group">
                        <label class="setting-label">行高: <span class="range-value" id="height-value">${this.config.lineHeight}</span></label>
                        <input type="range" id="height-range" min="1.2" max="2" step="0.1" value="${this.config.lineHeight}" style="width: 100%">
                    </div>
                `,
                showCancelButton: true,
                confirmButtonText: '保存',
                cancelButtonText: '重置',
                showCloseButton: true,
                width: 600,
                customClass: {
                    popup: 'mactype-popup',
                },
                footer: '<div style="text-align: center;font-size: 1em">Edge增强版 | <a href="https://www.youxiaohou.com/tool/install-mactype.html" target="_blank">使用说明</a> | Powered by <a href="https://www.youxiaohou.com">油小猴</a></div>',
                didOpen: () => {
                    this.bindSettingEvents();
                }
            }).then((res) => {
                if (res.isConfirmed) {
                    this.saveConfig();
                    this.applyStyle();
                }
                if (res.isDismissed && res.dismiss === "cancel") {
                    this.config = {
                        currentPreset: EDGE_CONFIG.isEdge ? 'edge' : 'balanced',
                        currentStroke: EDGE_CONFIG.isEdge ? 0.35 : 0.3,
                        currentShadow: '0 1px 2px rgba(0,0,0,0.1)',
                        currentSmooth: 'antialiased',
                        enableFontReplace: true,
                        enableShadow: true,
                        enableSmooth: true,
                        enableLetterSpacing: true,
                        letterSpacing: 0.02,
                        lineHeight: 1.6,
                        whiteList: this.config.whiteList,
                        blackList: this.config.blackList,
                        customFonts: false
                    };
                    this.saveConfig();
                    this.applyStyle();
                }
            });
        },

        bindSettingEvents() {
            // 预设按钮
            document.querySelectorAll('.preset-btn').forEach(btn => {
                btn.addEventListener('click', (e) => {
                    const preset = e.target.dataset.preset;
                    this.applyPreset(preset);
                    document.querySelectorAll('.preset-btn').forEach(b => b.classList.remove('active'));
                    e.target.classList.add('active');
                });
            });

            // 描边滑块
            const strokeRange = document.getElementById('stroke-range');
            const strokeValue = document.getElementById('stroke-value');
            strokeRange.addEventListener('input', (e) => {
                this.config.currentStroke = parseFloat(e.target.value);
                strokeValue.textContent = e.target.value;
                this.config.currentPreset = 'custom';
                this.updatePresetButtons();
                this.applyStyle();
            });

            // 字间距滑块
            const spacingRange = document.getElementById('spacing-range');
            const spacingValue = document.getElementById('spacing-value');
            spacingRange.addEventListener('input', (e) => {
                this.config.letterSpacing = parseFloat(e.target.value);
                spacingValue.textContent = e.target.value + 'em';
                this.applyStyle();
            });

            // 行高滑块
            const heightRange = document.getElementById('height-range');
            const heightValue = document.getElementById('height-value');
            heightRange.addEventListener('input', (e) => {
                this.config.lineHeight = parseFloat(e.target.value);
                heightValue.textContent = e.target.value;
                this.applyStyle();
            });

            // 开关
            document.getElementById('enable-shadow').addEventListener('change', (e) => {
                this.config.enableShadow = e.target.checked;
                this.applyStyle();
            });

            document.getElementById('enable-smooth').addEventListener('change', (e) => {
                this.config.enableSmooth = e.target.checked;
                this.applyStyle();
            });

            document.getElementById('enable-spacing').addEventListener('change', (e) => {
                this.config.enableLetterSpacing = e.target.checked;
                this.applyStyle();
            });

            document.getElementById('custom-fonts').addEventListener('change', (e) => {
                this.config.customFonts = e.target.checked;
                this.applyStyle();
            });
        },

        updatePresetButtons() {
            document.querySelectorAll('.preset-btn').forEach(btn => {
                btn.classList.remove('active');
                if (btn.dataset.preset === this.config.currentPreset) {
                    btn.classList.add('active');
                }
            });
        },

        applyPreset(presetName) {
            const preset = PRESETS[presetName];
            if (preset) {
                this.config.currentPreset = presetName;
                this.config.currentStroke = preset.stroke;
                this.config.currentShadow = preset.shadow;
                this.config.currentSmooth = preset.smooth;

                // 更新UI
                document.getElementById('stroke-range').value = preset.stroke;
                document.getElementById('stroke-value').textContent = preset.stroke;

                this.applyStyle();
            }
        },

        registerMenuCommand() {
            const host = location.host;
            const whiteList = this.config.whiteList;
            const blackList = this.config.blackList;

            if (whiteList.includes(host)) {
                GM_registerMenuCommand('💡 当前网站：白名单 ✔️', () => {
                    const index = whiteList.indexOf(host);
                    whiteList.splice(index, 1);
                    this.saveConfig();
                    history.go(0);
                });
            } else if (blackList.includes(host)) {
                GM_registerMenuCommand('🚫 当前网站：黑名单 ❌', () => {
                    const index = blackList.indexOf(host);
                    blackList.splice(index, 1);
                    this.saveConfig();
                    history.go(0);
                });
            } else {
                GM_registerMenuCommand('💡 当前网站：已启用', () => {
                    blackList.push(host);
                    this.saveConfig();
                    history.go(0);
                });
            }

            GM_registerMenuCommand('⚙️ 高级设置', () => {
                this.showSetting();
            });

            // 快速切换预设
            Object.entries(PRESETS).forEach(([key, preset]) => {
                if (key !== 'custom') {
                    GM_registerMenuCommand(`🎨 ${preset.name}`, () => {
                        this.config.currentPreset = key;
                        this.applyPreset(key);
                        this.saveConfig();
                    });
                }
            });
        },

        generateStyle() {
            const stroke = this.config.currentStroke;
            const shadow = this.config.enableShadow ? this.config.currentShadow : 'none';
            const smooth = this.config.enableSmooth ? this.config.currentSmooth : 'auto';
            const spacing = this.config.enableLetterSpacing ? this.config.letterSpacing : 'normal';
            const lineHeight = this.config.lineHeight;

            let fontRules = '';
            if (this.config.customFonts) {
                fontRules = `
                    /* 自定义字体 */
                    :root {
                        --font-sans: ${FONT_CONFIG.sans};
                        --font-serif: ${FONT_CONFIG.serif};
                        --font-mono: ${FONT_CONFIG.mono};
                    }

                    /* 基础字体应用 */
                    body, input, textarea, select, button {
                        font-family: var(--font-sans) !important;
                    }

                    /* 文章内容 */
                    article, .article, .content, .post,
                    [class*="article"], [class*="content"] {
                        font-family: var(--font-serif) !important;
                    }

                    /* 代码 */
                    pre, code, kbd, samp, tt,
                    .monospace, .mono,
                    [class*="code"], [class*="Code"] {
                        font-family: var(--font-mono) !important;
                    }
                `;
            }

            // Edge特定优化
            const edgeOptimizations = EDGE_CONFIG.isEdge ? `
                /* Edge浏览器特定优化 */
                body {
                    /* 启用DirectWrite */
                    -webkit-font-feature-settings: "kern" 1, "liga" 1, "calt" 1, "ss01" 1;
                    font-feature-settings: "kern" 1, "liga" 1, "calt" 1, "ss01" 1;

                    /* Edge ClearType优化 */
                    -webkit-font-smoothing: ${EDGE_CONFIG.isHighDPI ? 'antialiased' : smooth};

                    /* 优化中文渲染 */
                    text-rendering: optimizeLegibility;

                    /* Edge GPU加速 */
                    transform: translateZ(0);
                    will-change: transform;
                }

                /* 高DPI屏幕优化 */
                ${EDGE_CONFIG.isHighDPI ? `
                @media (-webkit-min-device-pixel-ratio: 2), (min-resolution: 192dpi) {
                    * {
                        -webkit-text-stroke: ${stroke * 0.8}px !important;
                        text-stroke: ${stroke * 0.8}px !important;
                    }
                }` : ''}

                /* Edge PDF阅读器排除 */
                .edge-pdf-viewer * {
                    -webkit-text-stroke: 0 !important;
                    text-stroke: 0 !important;
                    text-shadow: none !important;
                }
            ` : '';

            return `
                ${fontRules}

                /* 全局样式 */
                *:not([class*="icon"]):not([class*="Icon"]):not(i):not(svg):not(img):not(video) {
                    -webkit-text-stroke: ${stroke}px !important;
                    text-stroke: ${stroke}px !important;
                    text-shadow: ${shadow} !important;
                    -webkit-font-smoothing: ${smooth} !important;
                    -moz-osx-font-smoothing: ${smooth === 'antialiased' ? 'grayscale' : 'auto'} !important;
                    text-rendering: optimizeLegibility !important;
                }

                /* 正文优化 */
                body {
                    letter-spacing: ${spacing}em !important;
                    line-height: ${lineHeight} !important;
                    font-feature-settings: "liga" 1, "kern" 1, "calt" 1 !important;
                }

                ${edgeOptimizations}

                /* 选择文本 */
                ::selection {
                    color: #fff !important;
                    background: #338fff !important;
                }

                /* 排除特殊元素 */
                pre, code, [class*="code"] {
                    letter-spacing: normal !important;
                    font-feature-settings: "liga" 0, "calt" 0 !important;
                }

                /* Microsoft Office 365排除 */
                [class*="ms-"], [class*="o365"] {
                    -webkit-text-stroke: 0 !important;
                    text-stroke: 0 !important;
                }

                /* Swal样式 */
                .mactype-popup {
                    font-size: 14px !important;
                }

                /* 响应式优化 */
                @media screen and (min-width: 2560px) {
                    body {
                        -webkit-text-stroke: ${stroke * 1.1}px !important;
                        text-stroke: ${stroke * 1.1}px !important;
                    }
                }

                @media screen and (min-width: 3840px) {
                    body {
                        -webkit-text-stroke: ${stroke * 1.2}px !important;
                        text-stroke: ${stroke * 1.2}px !important;
                    }
                }

                /* 打印优化 */
                @media print {
                    * {
                        -webkit-text-stroke: 0 !important;
                        text-stroke: 0 !important;
                        text-shadow: none !important;
                    }
                }
            `;
        },

        applyStyle() {
            const style = this.generateStyle();
            util.addStyle('mactype-enhanced-style', 'style', style);
        },

        addPluginStyle() {
            if (document.head) {
                util.addStyle('swal-pub-style', 'style', GM_getResourceText('swalStyle'));
                this.applyStyle();
            }

            const headObserver = new MutationObserver(() => {
                if (document.head && !document.getElementById('mactype-enhanced-style')) {
                    util.addStyle('swal-pub-style', 'style', GM_getResourceText('swalStyle'));
                    this.applyStyle();
                }
            });

            headObserver.observe(document.documentElement, {childList: true, subtree: true});
        },

        isTopWindow() {
            return window.self === window.top;
        },

        shouldApply() {
            const host = location.host;
            if (this.config.whiteList.includes(host)) return true;
            if (this.config.blackList.includes(host)) return false;
            return true;
        },

        init() {
            // 显示浏览器信息
            if (EDGE_CONFIG.isEdge) {
                console.log(`Mactype助手增强版 - Edge ${EDGE_CONFIG.edgeVersion} 检测成功`);
                console.log(`高DPI模式: ${EDGE_CONFIG.isHighDPI ? '已启用' : '未启用'}`);
                console.log(`设备像素比: ${window.devicePixelRatio}`);
            }

            this.initValue();

            // Edge首次使用推荐
            if (EDGE_CONFIG.isEdge && !util.getValue('edge_optimized', false)) {
                this.config.currentPreset = 'edge';
                this.applyPreset('edge');
                this.saveConfig();
                util.setValue('edge_optimized', true);
            }

            if (this.isTopWindow()) {
                this.registerMenuCommand();
            }

            if (this.shouldApply()) {
                this.addPluginStyle();

                // Edge特定：监听缩放变化
                if (EDGE_CONFIG.isEdge) {
                    window.addEventListener('resize', () => {
                        if (window.devicePixelRatio !== EDGE_CONFIG.isHighDPI) {
                            EDGE_CONFIG.isHighDPI = window.devicePixelRatio > 1;
                            this.applyStyle();
                        }
                    });
                }
            }
        }
    };

    main.init();
})();