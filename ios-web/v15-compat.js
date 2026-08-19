(function () {
  'use strict';
  window.__BALI_STOCK_V15_COMPAT__ = '15.0';

  var originalGetElementById = document.getElementById.bind(document);
  var aliases = {
    v14Photo: 'v14pcPhoto',
    v14Edit: 'v14pcEdit',
    v14Spot: 'v14pcStocktake'
  };

  document.getElementById = function (id) {
    var direct = originalGetElementById(id);
    if (direct) return direct;
    var alias = aliases[id];
    return alias ? originalGetElementById(alias) : null;
  };
})();
