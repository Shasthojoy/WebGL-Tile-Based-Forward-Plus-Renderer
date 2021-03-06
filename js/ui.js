// var cfg;

(function() {
    'use strict';

    var FPR = ForwardPlusRenderer;

    var Cfg = function() {
        // TODO: Define config fields and defaults here
        this.curPipeline = 'forwardPlusPipeline';
        this.lightPositionDebug = true;
        this.enableEffect0 = false;
    };

    var init = function() {
        var cfg = FPR.cfg = new Cfg();

        var gui = new dat.GUI();
        // TODO: Define any other possible config values
        var pipeline = gui.add(cfg, 'curPipeline', {
            '0 Forward Plus': 'forwardPlusPipeline',
            '1 Forward Plus Tile Light Debug': 'forwardPlusTileLightDebugPipeline',
            '2 Forward': 'forwardPipeline',
            '3 Depth Debug': 'depthDebugPipeline'
        });

        pipeline.onChange(FPR.setUniformDirty);

        gui.add(cfg, 'lightPositionDebug');

        
        // TODO: add more effects toggles and parameters here
        var eff0 = gui.addFolder('EFFECT NAME HERE');
        eff0.open();
        eff0.add(cfg, 'enableEffect0');
    };

    globalInitHandlers.push(init);
})();
