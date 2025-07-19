// ==UserScript==
// @name         吉祥航空内网字体优化
// @namespace    http://tampermonkey.net/
// @version      1.0
// @description  优化吉祥航空内部系统的字体显示
// @author       You
// @match        https://cabinternal.juneyaoair.com/*
// @match        http://cabinternal.juneyaoair.com/*
// @match        *://*.juneyaoair.com/*
// @grant        none
// @run-at       document-start
// ==/UserScript==

(function() {
    'use strict';

    // 创建并插入样式
    const style = document.createElement('style');
    style.textContent = `
        /* ===== 全局字体优化 ===== */
        * {
            /* 字体栈 - 优先使用更纱黑体 */
            font-family: "更纱黑体 UI SC", "Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Segoe UI", sans-serif !important;
        }
        
        /* ===== 基础样式强化 ===== */
        body {
            /* 字体渲染优化 */
            -webkit-font-smoothing: antialiased !important;
            -moz-osx-font-smoothing: grayscale !important;
            text-rendering: optimizeLegibility !important;
            
            /* 轻微描边增强清晰度 */
            -webkit-text-stroke: 0.35px !important;
            text-stroke: 0.35px !important;
            
            /* 字体大小和行高 */
            font-size: 14px !important;
            line-height: 1.6 !important;
            
            /* 字间距微调 */
            letter-spacing: 0.02em !important;
            
            /* 字体特性 */
            font-feature-settings: "liga" 1, "kern" 1, "calt" 1 !important;
            
            /* 颜色加深 */
            color: #333 !important;
        }
        
        /* ===== 表格优化 ===== */
        table, .table {
            font-size: 13px !important;
            color: #333 !important;
        }
        
        th {
            font-weight: 600 !important;
            color: #222 !important;
        }
        
        td {
            font-weight: normal !important;
        }
        
        /* ===== 链接优化 ===== */
        a {
            font-weight: 500 !important;
            color: #0066cc !important;
        }
        
        a:hover {
            color: #0052a3 !important;
            text-decoration: underline !important;
        }
        
        /* ===== 标题优化 ===== */
        h1, h2, h3, h4, h5, h6,
        .index_title h4 {
            font-weight: 600 !important;
            color: #222 !important;
            letter-spacing: 0 !important;
        }
        
        /* ===== 导航菜单优化 ===== */
        .menu ul li a,
        .sub_menu a {
            font-weight: 500 !important;
            font-size: 14px !important;
        }
        
        /* ===== 按钮优化 ===== */
        button, .btn, input[type="button"], input[type="submit"] {
            font-weight: 500 !important;
            font-size: 14px !important;
        }
        
        /* ===== 输入框优化 ===== */
        input, textarea, select {
            font-family: inherit !important;
            font-size: 14px !important;
            font-weight: normal !important;
        }
        
        /* ===== 特定区域优化 ===== */
        /* 个人信息区域 */
        .index_user_text h5 {
            font-size: 16px !important;
            font-weight: 600 !important;
            color: #222 !important;
        }
        
        .welcome {
            font-size: 14px !important;
            font-weight: 500 !important;
        }
        
        /* 数字显示 */
        .num {
            font-weight: 600 !important;
            font-size: 18px !important;
            font-variant-numeric: tabular-nums !important;
        }
        
        /* 日期显示 */
        .date p {
            font-weight: 500 !important;
            font-size: 14px !important;
        }
        
        /* 列表项 */
        .index_sec_list li {
            font-size: 13px !important;
            line-height: 1.8 !important;
        }
        
        /* 证件提醒 - 警告颜色保持但加粗 */
        .indextextred {
            font-weight: 600 !important;
        }
        
        .indextextyellow {
            font-weight: 600 !important;
        }
        
        /* ===== 响应式优化 ===== */
        @media screen and (min-width: 1920px) {
            body {
                font-size: 15px !important;
                -webkit-text-stroke: 0.4px !important;
                text-stroke: 0.4px !important;
            }
            
            table, .table {
                font-size: 14px !important;
            }
        }
        
        /* ===== 打印优化 ===== */
        @media print {
            * {
                -webkit-text-stroke: 0 !important;
                text-stroke: 0 !important;
                font-weight: normal !important;
            }
            
            h1, h2, h3, h4, h5, h6 {
                font-weight: bold !important;
            }
        }
        
        /* ===== 修复可能的样式冲突 ===== */
        * {
            text-shadow: none !important; /* 移除可能的文字阴影 */
        }
        
        /* 确保重要文字不会太细 */
        b, strong {
            font-weight: 600 !important;
        }
    `;
    
    // 尽早插入样式
    if (document.head) {
        document.head.insertBefore(style, document.head.firstChild);
    } else {
        // 如果head还不存在，等待DOM加载
        const observer = new MutationObserver((mutations, obs) => {
            if (document.head) {
                document.head.insertBefore(style, document.head.firstChild);
                obs.disconnect();
            }
        });
        observer.observe(document.documentElement, {childList: true, subtree: true});
    }
    
    // 页面加载完成后的额外处理
    document.addEventListener('DOMContentLoaded', function() {
        // 检查是否有内联样式覆盖
        const allElements = document.querySelectorAll('*');
        allElements.forEach(el => {
            // 移除可能导致字体变细的内联样式
            if (el.style.fontWeight === '300' || el.style.fontWeight === '100' || el.style.fontWeight === '200') {
                el.style.fontWeight = 'normal';
            }
        });
        
        console.log('吉祥航空内网字体优化已应用');
    });
})();