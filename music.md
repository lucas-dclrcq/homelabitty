---
title: Music
description: 
published: true
date: 2025-04-16T11:50:59.670Z
tags: 
editor: markdown
dateCreated: 2025-01-03T23:23:51.047Z
---

# 🎵 Musique

La musique est hébergée sur [Navidrome](https://github.com/navidrome/navidrome) : [music.hoohoot.org](https://music.hoohoot.org)  
👉 Pour te connecter, utilise le mot de passe habituel.  

---

## 🔄 Utiliser un client compatible Subsonic  

Navidrome est compatible avec les clients [Subsonic](https://github.com/topics/subsonic-client), ce qui permet d’accéder à la musique depuis :  
✔️ Un logiciel sur PC (Linux, macOS, Windows)  
✔️ Une application mobile (Android, iOS)  

### 🔧 Configuration d'un client Subsonic  

Les clients Subsonic ne prennent pas en charge l’authentification via SSO. Tu dois donc définir un mot de passe spécifique.  

1. Ouvre Navidrome et clique sur l'icône utilisateur en haut à droite :  

![capture_d’écran_2025-02-17_à_22.49.58.png](/capture_d’écran_2025-02-17_à_22.49.58.png)

2. Sélectionne **Change Password** et définis un nouveau mot de passe :  

![capture_d’écran_2025-02-17_à_22.49.41.png](/capture_d’écran_2025-02-17_à_22.49.41.png)

3. Utilise ce mot de passe dans ton client Subsonic avec l'URL suivante : https://music-api.hoohoot.org 


### 📌 Clients recommandés  

- **Linux** : [Feishin](https://github.com/jeffvli/feishin) , [SuperSonic](https://github.com/dweymouth/supersonic)
- **Android** : [Tempo](https://github.com/CappielloAntonio/tempo)  

## Télécharger de la musique

Pour télécharger de la musique on utilise l'interface [Lidarr](https://lidarr.hoohoot.org/)

![lidarr_home.png](/lidarr_home.png)

Utilise le champs recherche pour rechercher l'artiste/l'album que tu souhaites

### I. Recherche par artiste

La recherche lidarr permet de rechercher par artiste puis de selectionner les albums que tu veux télécharger. Il y a deux possibilité : soit l'artiste a déjà été ajouté par l'un de nous, soit tu es le premier à le faire

####	a/ L'artiste n'a pas encore été indexé

Tu es le premier à rechercher cet artiste. Il va falloir l'indexer, c'est à dire l'ajouter à la liste des artistes connu·e·s par lidarr

La recherche te proposera différent match pour ton artiste

![patrick_bruel.png](/patrick_bruel.png)

Quand tu as trouvé le bon match tu cliques dessus. Une fenêtre s'ouvre pour paramétrer comment tu veux indexer cet artiste, c'est à dire :
- Dans quel dossier sur le serveur tu veux l'ajouter (automatiquement, il sera rangé dans un dossier à son nom
- Si tu souhaite monitorer les sorties de cet artiste, c'est à dire indexer et télécharger automatiquement les nouvelles sorties
- La qualité de fichier audio que tu souhaites rechercher
- Le type de metadata que tu veux

> ATTENTION !
> Sur notre serveur, on a des règles ! Pour ne pas risquer de polluer notre mediathèque avec des centaines de titres téléchargés automatiquement, on désactive systématiquement le monitoring. 
De même, on ne télécharge que des fichiers en qualité Lossless.
Si tu as un doute, tu peux juste suivre l'exemple suivant :
{.is-warning}


![monitor.png](/monitor.png)

Une fois que c'est fait, cliques sur "Add". Tu reviens sur ton menu de recherche mais désormais, le match que tu as choisi a un ✔️ pour indiquer qu'il est indexé. 

![indexed.png](/indexed.png)


La prochaine fois que tu voudras télécharger un album de cet artiste, il apparaitra automatiquement avec sa photo quand tu commenceras à taper son nom dans la barre de recherche

####	b/ L'artiste a été indexé

En cliquant sur l'artiste indexé dans ta liste de match, ou directement dans la suggestion de recherche, tu arrives sur la liste du contenu connu de ton artiste

![content.png](/content.png)

À côté de chaque titre d'album tu vois le status (téléchargé ou non) ainsi qu'une petite loupe. Pour rechercher et télécharger un album il te suffit de cliquer sur la loupe.

Si tu veux vérifier le contenu de l'album tu peux cliquer sur le titre de l'album pour voir la liste des titres. Si tout roule, il te suffit de cliquer sur l'icone "Search album" en haut à gauche pour rechercher et télécharger ton album.

![album.png](/album.png)

une fois la recherche lancée, deux possibilités :

1. Il trouve ton album directement. Il va alors l'ajouter en queue pour le télécharger. Tu peux aller voir la queue dans le menu Activity dans la bar d'outils à gauche




## Uploader de la musique

TBD

