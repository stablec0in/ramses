// Uniswap V3 helper functions
import { whype, usdt } from '../scripts/config.js';

// TODO : ici on suppose que on rebalance la position lorsque elle est out of range, il faudrait faire les calculs (fonction 2) 
// dans le cas a0*a1 not 0. 


// petit probleme je vais comme si je swap au prix idéal, ce qui crée un petit décalage.
// je pense que je dois mettre 0.5 de slipage sur le prix
function toSqrtPrice(tick) {
  return Math.pow(1.0001, tick / 2);
}
const slippage = 0.005;
// Etant donnée (tick, ta,tb) : tick courant tick bas et tick haut de la positon et L la liquidité (au sens sans du contrat) donne
// la quantité de token de la position (n'inclue pas les fees accumuler).

function calculateExit({ tick, ta, tb, liquidity }) {
  const sqrtP = toSqrtPrice(tick);
  const sqrtPa = toSqrtPrice(ta);
  const sqrtPb = toSqrtPrice(tb);
  let a0, a1;
  if (tick < ta) {
    a0 = liquidity * (1 / sqrtPa - 1 / sqrtPb);
    a1 = 0;
  } else if (tick > tb) {
    a0 = 0;
    a1 = liquidity * (sqrtPb - sqrtPa);
  } else {
    a0 = liquidity * (1 / sqrtP - 1 / sqrtPb);
    a1 = liquidity * (sqrtP - sqrtPa);
  }
  return { a0, a1 };
}


// Etant donné a0, a1 tel que a0*a1=0, calcul le montant x de token qu'il faut swap pour 
// (a-x,px) ou (x/p , b-x) soit conforme au range (ta,tb) pour le tick courant 
// Ici il y a un probleme de swap donc j'introdujis un petit slippage.
// Faudrait que je fasse un truc un peu différent pour augmenter la précission
// 1. faire ce calcul, 2. simuler le swap 3. obtenir le prix réel du swap et modifier le slipage comme ca. 
// ca devrait permettre d'optimiser un peu mieux. 

function simulateRebalance({ tick, ta, tb, a0 = 0, a1 = 0 }) {
  const sqrtP = toSqrtPrice(tick);
  const sqrtPa = toSqrtPrice(ta);
  const sqrtPb = toSqrtPrice(tb);
  let p = sqrtP ** 2;

  const alpha = (1 / sqrtP) - (1 / sqrtPb);
  const beta = sqrtP - sqrtPa;

  if (a0 > 0 && a1 === 0) {
    p = (1-slippage) *p;
    // x est le montant a swaper pour obtenir une posiion équilibré dans le range.
    /*
      Qu'un ce que ca change si j'ai (a0,a1) ? 
          (a0-x,a1+px) proportionnelle a (alpha,beta)

          alpha * (a1+px) = beta * (a0-x) 

          -alpha a1 +beta a0 =  beta x +alpha px

          x = (beta a0 - alpha a1) / (beta+alpha * p)

    En gros, la condition pour savoir si je swap 0 to 1 c'est que 
            (alpha  a0)
        det (beta  a1)     soit negatid 
            
      
      Si L=1 alors 
        alpha = (1 / sqrtP) - (1 / sqrtPb);
        beta  =  sqrtP - sqrtPa;
        est une position compatible avec le range [ta,tb] et tick.
        Ma position doit etre proportielle a celle-ci
        je cherche x tel que :
          (a0-x,x*p) proportionelle a (alpha,beta)
    */
    const x = (beta * a0) / (beta + alpha * p);
    return {
      postSwap: {
        amountIn:x,
        token0: a0 - x,
        token1: x * p
      }
    };
  } else if (a1 > 0 && a0 === 0) {
    p = (1+slippage)*p;
    const y = (alpha * a1) / ((beta / p) + alpha);
    return {
      postSwap: {
        amountIn: y,
        token0: y / p,
        token1: a1 - y
      }
    };
  } else {
    return {
      postSwap: {
        amountIn:0,
        token0: a0,
        token1: a1
      }
    };
  }
}

// ici juste l'enchainement des deux fonctions. 
function calculateLiquidity({ tick, ta, tb, amount0, amount1 }) {
  const sqrtP = toSqrtPrice(tick);
  const sqrtPa = toSqrtPrice(ta);
  const sqrtPb = toSqrtPrice(tb);

  const [sqrtA, sqrtB] = sqrtPa < sqrtPb ? [sqrtPa, sqrtPb] : [sqrtPb, sqrtPa];

  if (tick <= ta) {
    return amount0 / ((1 / sqrtA) - (1 / sqrtB));
  } else if (tick >= tb) {
    return amount1 / (sqrtB - sqrtA);
  } else {
    const l0 = amount0 / ((1 / sqrtP) - (1 / sqrtB));
    const l1 = amount1 / (sqrtP - sqrtA);
    return Math.min(l0, l1);
  }
}

export function repositionLiquidity({ tick, ta, tb, nta, ntb, liquidity }) {
  const { a0, a1 } = calculateExit({ tick, ta, tb, liquidity });

  let swapResult;
  let tokenIn;
  let tokenOut;
  if (a0 > 0 && a1 === 0) {
    tokenIn = whype;
    tokenOut = usdt;
    // dans le cas la direction du swap c'est token0 -> token1 
    swapResult = simulateRebalance({ tick, ta: nta, tb: ntb, a0 });
  } else if (a1 > 0 && a0 === 0) {
    tokenIn = usdt;
    tokenOut = whype;
    swapResult = simulateRebalance({ tick, ta: nta, tb: ntb, a1 });
  } else {
    throw new Error("Expected out-of-range position (a0 * a1 == 0)");
  }
  
  const { token0, token1,amountIn } = swapResult.postSwap;
  const newLiquidity = calculateLiquidity({ tick, ta: nta, tb: ntb, amount0: token0, amount1: token1 });

  return {
    amountIn: parseInt(amountIn),
    tokenIn,
    tokenOut,
    newLiquidity
  };
}
/*
// Example usage:
const result = repositionLiquidity({
  tick:-237582,
  ta: -237900,
  tb: -237600,
  nta: -237700,
  ntb: -237400,
  liquidity: 21319375676934521
});

console.log(result);
*/
