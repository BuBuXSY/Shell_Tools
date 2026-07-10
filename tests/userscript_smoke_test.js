#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.resolve(__dirname, '..');

function createHarness({edge = false, savedConfig = null, inlineElements = []} = {}) {
    const elements = new Map();
    const observers = [];
    const documentListeners = new Map();
    const windowListeners = new Map();
    const menuCommands = new Map();
    const store = new Map();
    let styleWrites = 0;
    let head = null;

    if (savedConfig) store.set('enhanced_config', savedConfig);

    const document = {
        documentElement: {},
        readyState: 'loading',
        get head() {
            return head;
        },
        createElement(tagName) {
            let text = '';
            return {
                tagName: tagName.toUpperCase(),
                id: '',
                rel: '',
                href: '',
                get textContent() {
                    return text;
                },
                set textContent(value) {
                    text = value;
                    styleWrites += 1;
                }
            };
        },
        getElementById(id) {
            return elements.get(id) || null;
        },
        querySelectorAll(selector) {
            return selector === '[style]' ? inlineElements : [];
        },
        addEventListener(type, callback) {
            documentListeners.set(type, callback);
        }
    };

    const window = {
        devicePixelRatio: 1,
        alert() {},
        addEventListener(type, callback) {
            windowListeners.set(type, callback);
        }
    };
    window.self = window;
    window.top = window;

    class MutationObserver {
        constructor(callback) {
            this.callback = callback;
            this.disconnected = false;
            observers.push(this);
        }

        observe() {}

        disconnect() {
            this.disconnected = true;
        }
    }

    const context = {
        console,
        document,
        history: {go() {}},
        location: {host: 'example.com'},
        MutationObserver,
        navigator: {
            userAgent: edge
                ? 'Mozilla/5.0 Chrome/130.0.0.0 Edg/130.0.0.0'
                : 'Mozilla/5.0 Chrome/130.0.0.0'
        },
        window,
        GM_getValue(name) {
            return store.get(name);
        },
        GM_setValue(name, value) {
            store.set(name, value);
        },
        GM_registerMenuCommand(label, callback) {
            menuCommands.set(label, callback);
        },
        GM_getResourceText() {
            return '.swal2-container { display: grid; }';
        }
    };

    return {
        context,
        documentListeners,
        elements,
        menuCommands,
        observers,
        window,
        windowListeners,
        createHead() {
            head = {
                firstChild: null,
                appendChild(element) {
                    elements.set(element.id, element);
                },
                insertBefore(element) {
                    elements.set(element.id, element);
                }
            };
        },
        getStyleWrites() {
            return styleWrites;
        }
    };
}

function runScript(fileName, harness) {
    const source = fs.readFileSync(path.join(ROOT, fileName), 'utf8');
    vm.runInNewContext(source, harness.context, {filename: fileName});
}

function testMactypeDocumentStart() {
    const harness = createHarness({
        edge: true,
        savedConfig: {
            currentPreset: 'balanced',
            currentStroke: 0.3,
            currentShadow: '0 1px 2px rgba(0,0,0,0.1)',
            currentSmooth: 'antialiased',
            enableFontReplace: true,
            enableShadow: true,
            enableSmooth: true,
            enableLetterSpacing: false,
            letterSpacing: 0.02,
            lineHeight: 1.6,
            whiteList: [],
            blackList: [],
            customFonts: false
        }
    });

    runScript('Mactype助手增强版 (Edge优化)-1.0.0.user.js', harness);
    assert.strictEqual(harness.observers.length, 1, 'head observer should be registered');

    harness.createHead();
    harness.observers[0].callback();
    assert.ok(harness.observers[0].disconnected, 'head observer should disconnect after injection');

    const style = harness.elements.get('mactype-enhanced-style');
    assert.ok(style, 'Mactype style should be injected');
    assert.match(style.textContent, /letter-spacing:\s+normal !important/);
    assert.doesNotMatch(style.textContent, /normalem/);

    const writesBeforeResize = harness.getStyleWrites();
    harness.windowListeners.get('resize')();
    assert.strictEqual(harness.getStyleWrites(), writesBeforeResize, 'same DPI class should not rewrite styles');

    harness.window.devicePixelRatio = 2;
    harness.windowListeners.get('resize')();
    assert.ok(harness.getStyleWrites() > writesBeforeResize, 'DPI class change should refresh styles');

    const lightPreset = [...harness.menuCommands.entries()]
        .find(([label]) => label.includes('轻度优化'));
    assert.ok(lightPreset, 'quick preset menu should be registered');
    assert.doesNotThrow(() => lightPreset[1](), 'quick preset should work without an open settings dialog');
}

function testMactypeBlacklistOnFirstEdgeRun() {
    const harness = createHarness({
        edge: true,
        savedConfig: {
            blackList: ['example.com'],
            whiteList: []
        }
    });
    harness.createHead();

    runScript('Mactype助手增强版 (Edge优化)-1.0.0.user.js', harness);
    assert.ok(
        !harness.elements.has('mactype-enhanced-style'),
        'blacklisted host should not receive styles during first-run preset initialization'
    );
}

function testJunyaoDocumentStart() {
    const thinElement = {
        style: {
            fontWeight: '300',
            setProperty(name, value, priority) {
                assert.strictEqual(name, 'font-weight');
                assert.strictEqual(priority, 'important');
                this.fontWeight = value;
            }
        }
    };
    const harness = createHarness({inlineElements: [thinElement]});

    runScript('junyaoairwebsite-intranet-optimization1.0.user.js', harness);
    assert.strictEqual(harness.observers.length, 1, 'head observer should be registered');

    harness.createHead();
    harness.observers[0].callback([], harness.observers[0]);
    assert.ok(harness.elements.has('junyao-font-optimization-style'), 'Junyao style should be injected');

    harness.documentListeners.get('DOMContentLoaded')();
    assert.strictEqual(thinElement.style.fontWeight, 'normal');
}

testMactypeDocumentStart();
testMactypeBlacklistOnFirstEdgeRun();
testJunyaoDocumentStart();
console.log('userscript smoke tests passed');
