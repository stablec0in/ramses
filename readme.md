Plan pour faire les choses proprement.

Niveau smart-contrat si on veut faire un truc un peu plus générique. Il faut un contrat Manager dont le rôle va etre de gérer les dex, pools et assets en whitelist (avec un role admin).
Il faut aussi une fonction Initialize_rebalancer qu'un utilisateur peut appeler, cette fonction va deployer un contrat rebalancer avec les parametre que l'utilisateur veut.

Ensuite, l'utilisateur a accès a la fonction rebalance du contrat, ou il peut faire appel a un service de bot (payant car le bot paye les fees). Il doit pouvoir update
une strategie 

1.neutre tick + ou -  delta. 
2. bull  tick + 2delta - delta. 
3. bear tick +delta  - 2 delta.

