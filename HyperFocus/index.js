const cssProperty = function (node, property) {
    if (node instanceof Element) {
        return window.getComputedStyle(node, null).getPropertyValue(property)
    } else {
        return null
    }
}

const appendCssNode = function (css) {
    const newScript = document.createElement('style')
    const content = document.createTextNode(css)
    newScript.appendChild(content)
    document.head.appendChild(newScript)
}

class DOMWalker {
    constructor(processors) {
        this.processors = processors
    }

    walk(node) {
        this.processors.forEach(p => p.process(node))
        if (node.childNodes) node.childNodes.forEach(node => this.walk(node))
        else console.log(`could not walk ${node}`)
    }
}

class ColorAggregator {
    constructor() {
        this.frontColors = new Set()
        this.backColors = new Set()
        this.borderColors = new Set()
    }

    process(node) {
        const fcColor = tinycolor(cssProperty(node, "color"))
        if (fcColor.isValid()) {
            this.frontColors.add(fcColor.toHexString())
        }

        const bcColor = tinycolor(cssProperty(node, "background-color"))
        this.backColors.add(bcColor?.toHexString())
        if (bcColor.isValid()) {
            this.backColors.add(bcColor.toHexString())
        }

        const borderColor = tinycolor(cssProperty(node, "border-color"))
        if (borderColor.isValid()) {
            this.borderColors.add(borderColor.toHexString())
        }
    }
}

class NodeInverter {
    process(node) {
        const fcColor = Color.fromCss(node, "color", DEFAULT_FRONT)
        if (node.classList && fcColor?.plum1() < 0.5) {
            node.classList.add('hyperfocus-lighten')
            node.classList.add('hyperfocus-darken')
            const borderColor = Color.fromCss(node, "border-color", DEFAULT_BORDER)
            if (borderColor?.plum1() > 0.5) {
                node.classList.add("hyperfocus-soften-border")
            }
        }
    }
}

const f = function (color) {
    const tc = tinycolor(color)
    return {
        brightness: tc.getBrightness(),
        lum: tc.getLuminance(),
        alpha: tc.getAlpha(),
        isDark: tc.isDark(),
        isLight: tc.isLight()
    }
}

class BrightnessAdjuster {

    constructor() {
        this.classMap = {}
    }

    appendCss(classname, css) {
        if (!this.classMap[classname]) {
            appendCssNode(css)
            this.classMap[classname] = true
        }
    }

    process(node) {
        const bcColor = tinycolor(cssProperty(node, "background-color"))
        const fcColor = tinycolor(cssProperty(node, "color"))
        // if (bcColor.isLight()) {
        if (bcColor.getLuminance() > 0.7) {
            const amp = (bcColor.getLuminance() - 0.5) * 100
            const darkColor = bcColor.darken(amp)

            this.appendCss(`hf-bc-${darkColor.toHex()}`, `
                .hf-bc-${darkColor.toHex()} {
                    background-color: ${darkColor.toHexString()} !important; 
            };`)
            node.classList.add(`hf-bc-${darkColor.toHex()}`)

            //            if (!tinycolor.isReadable(darkColor, fcColor)) {
            //
            //                const betterFc = tinycolor.mostReadable(darkColor,
            //                    [fcColor],
            //                    {includeFallbackColors: true})
            //
            //                this.appendCss(`hf-fc-${betterFc.toHex()}`, `
            //                .hf-fc-${betterFc.toHex()} {
            //                    color: ${betterFc.toHexString()} !important;
            //                };`)
            //                node.classList.add(`hf-fc-${betterFc.toHex()}`)
            //            }
        }
    }
}

function isDarkModeEnabled() {
    return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches
}

function main() {
    const GLOBAL_CSS = `
html, body :not(iframe) {
     background-color: #181a1b !important;
     color: #e8e6e3 !important;
     border-color: #38383AFF !important;
};

img {
    filter: brightness(80%) !important;
}
`;

    const targetNode = document.documentElement
    const config = { childList: true, subtree: true };

    const walker = new DOMWalker([
        new ColorAggregator(),
        new BrightnessAdjuster()
    ])

    const observer = new MutationObserver((mutationsList,
        observer) => {
        for (const mutation of mutationsList) {
            mutation.addedNodes.forEach(node => walker.walk(node))
        }
    });
    // Start observing the target node for configured mutations
    observer.observe(targetNode, config);

    const styleObserver = new MutationObserver((d, observer) => {
        if (document.head && document.body) {
            appendCssNode(GLOBAL_CSS);
            observer.disconnect()
        }
    })

    styleObserver.observe(targetNode, config)
}

function onlyDimImages() {
    const targetNode = document.documentElement
    const config = { childList: true, subtree: true };

    const dimImages = `
        img {
            filter: brightness(80%) !important;
        }
    `
    
    const styleObserver = new MutationObserver((d, observer) => {
        if (document.head && document.body) {
            appendCssNode(dimImages);
            observer.disconnect()
        }
    })

    styleObserver.observe(targetNode, config)
}

function findInPage(text) {
    var instance = new Mark(document.querySelectorAll("body"));
    instance.mark(text || window.getSelection().toString())
}


(function () {
    const hosts = ["stack", "yahoo"]

    if (isDarkModeEnabled() && hosts.filter(d => window.location.host.indexOf(d) !== -1).length > 0) {
        main()
    } else {
        onlyDimImages()
        DarkReader?.enable()
    }
})();
