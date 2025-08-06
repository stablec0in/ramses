Plan pour faire les choses proprement.

Niveau smart-contrat si on veut faire un truc un peu plus générique. Il faut un contrat Manager dont le rôle va etre de gérer les dex, pools et assets en whitelist (avec un role admin).
Il faut aussi une fonction Initialize_rebalancer qu'un utilisateur peut appeler, cette fonction va deployer un contrat rebalancer avec les parametre que l'utilisateur veut.

Ensuite, l'utilisateur a accès a la fonction rebalance du contrat, ou il peut faire appel a un service de bot (payant car le bot paye les fees). Il doit pouvoir update
une strategie 

1.neutre tick + ou -  delta. 
2. bull  tick + 2delta - delta. 
3. bear tick +delta  - 2 delta.


contexte : Une pool de liquidité avec deux tokens A et B, tu as (a,b) en tokens (a token a et b token b). Tu veux faire une pool (ta,tb,t)  
avec ta : le tick du bas, tb le tick du haut et t le current tick.
Tu veux max, donc en gros faire un swap pour maximiser ta liquidité. Comment on fait les calculs ?

Les formules d'uniswap il existe L (la liquidité) tel que 

amount_a = L (1 / sqrtP - 1 / sqrtPb)
amount_b = L(sqrtP-sqrtPa)

avec sqrtP = 1.0001**(tick/2) et pareil avec sqrtPa et sqrtPb
et p = sqrtP * * 2  = 1.0001**(tick)
Le problème c'est qu'on connait pas L a l'avance. Mais les positions  (de même configuration) sont toutes proportionnelles. Du coup je fais L=1

On pose :
alpha = 1 / sqrtP - 1 / sqrtPb
beta   =  sqrtP-sqrtPa

On pose : T = (alpha,beta) le vecteur. Et du coup, nous on cherche x tel que : 

(a-x,b+px) proportionnelle a T. Un petit coup de déterminant 2 x 2 :

tu obtiens : x = (beta  a - alpha  b) / (beta + alpha * p)

Ici attention c'est un x signé. Et donc x > 0 signifie que tu dois swap A vers B si et seulement si  beta a - alpha b > 0, et tu as la quantité donné par x.
Si x < 0, alors tu dois swap B vers a en quantité de x/p. 
