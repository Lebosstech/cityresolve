# Patch garde-fou contenu insuffisant — notes (fusion E4 + garde-fou, poussé sur main)

Dossier : `patch-guardrail-app/` = copie complète de l'application du
miroir du dépôt (`repo-mirror/app`, lecture seule, intact — hash
`grouping.dart` du miroir vérifié inchangé après travaux), avec les
modifications ci-dessous. Aucun push GitHub, aucun envoi à ChatGPT.
Aucune clé lue, copiée ou journalisée (les tests utilisent des clés
factices déjà présentes dans le code d'origine, ex. `wrong-key`).

## 1. La règle, exactement

Un signalement dont le texte, après passage en minuscules, contient
**moins de 2 caractères alphanumériques** (lettres accentuées comprises,
`[a-zàâäéèêëîïôöùûüç0-9]`) ne peut **JAMAIS** être fusionné avec un autre
signalement, quelle que soit la méthode (classique, synonymes, Meta).
Il reste singleton, avec le statut explicite :
`garde-fou-contenu-insuffisant : signalement non fusionnable, contenu
insuffisant, à vérifier`, et un signal à vérifier (`uncertain = true`).

Cas couverts : texte vide, ponctuation/espaces seuls, un seul caractère
(ex. « a »). Cas NON couvert par construction : un texte de 2 caractères
ou plus passe le garde-fou, même s'il est vide de sens (ex. « ab »).
Le garde-fou vise l'absence de contenu, pas la qualité du contenu.

## 2. Fichiers modifiés

- `app/lib/grouping.dart` :
  - `hasInsufficientContent(String text)` : la règle ci-dessus.
  - `guardrailReason` : le libellé explicite du statut.
  - `groupReports` : aucune union impliquant un contenu insuffisant,
    quelle que soit la distance, le temps ou la similarité (la règle ne
    dépend d'aucun seuil) ; un singleton à contenu insuffisant porte la
    raison garde-fou.
  - `applyContentGuardrail(reports, groups)` : filtre déterministe
    post-modèle (ou post-classique). Tout groupe contenant un contenu
    insuffisant est découpé en singletons ; les singletons concernés
    portent la raison garde-fou et une justification
    « Garde-fou : fusion proposée annulée (contenu insuffisant) » avec
    la proposition d'origine conservée ; les groupes sans contenu
    insuffisant sont retournés inchangés. Retourne aussi
    `cancelledMerges` = nombre de groupes multi-signalements découpés,
    la trace comptable de l'annulation.
- `app/lib/meta_connector.dart` :
  - import de `grouping.dart` (aucun cycle : grouping n'importe que types).
  - `proposeMatchingWithMeta` : après construction des groupes Meta,
    application systématique de `applyContentGuardrail` avant retour.
    Même si le modèle propose la fusion, elle est annulée. L'annulation
    est journalisée dans les groupes retournés eux-mêmes (raison +
    justification), qui sont persistés par le serveur dans `metaGroups` :
    elle est donc vérifiable groupe par groupe, sans dépendre de
    l'incertitude du modèle.
  - Choix documenté : un pré-filtre (ne pas envoyer ces textes au modèle)
    n'a pas été choisi. Il masquerait la proposition du modèle au lieu
    de la corriger visiblement, et il empêcherait de compter les
    annulations. Le post-filtre est le complément, pas le remplaçant,
    d'un éventuel pré-filtre futur.
- `app/test/test_all.dart` : section 23, tests T23a à T23g (voir §3).
- `app/test/test_exploratoire.dart` : cas E9 (voir §3).

Le serveur (`bin/server.dart`) n'a pas eu besoin de modification : il
utilise `groupReports` pour le classique et `proposeMatchingWithMeta`
pour Meta, donc les deux chemins sont couverts par les deux points
ci-dessus.

## 3. Tests exécutés, résultats réels

Commandes (SDK Dart de `~/workspace/cityresolve/dart-sdk`) :

```text
cd ~/workspace/cityresolve/patch-guardrail-app/app
~/workspace/cityresolve/dart-sdk/bin/dart test/test_all.dart
~/workspace/cityresolve/dart-sdk/bin/dart test/test_exploratoire.dart
~/workspace/cityresolve/dart-sdk/bin/dart analyze lib/grouping.dart lib/meta_connector.dart test/test_all.dart test/test_exploratoire.dart
```

- `test_all.dart` : **82 PASS, 0 FAIL** (72 d'origine + 10 nouveaux T23).
  - T23a : deux textes vides ne fusionnent pas ; singletons marqués garde-fou.
  - T23b : texte vide contre texte non vide ne fusionne pas.
  - T23c : un seul caractère (« a » contre « a ») ne fusionne pas.
  - T23d : ponctuation/espaces seuls ne fusionnent pas.
  - T23e : texte normal non affecté (deux textes normaux identiques fusionnent).
  - T23f : le filtre post-modèle annule une fusion factice de deux vides
    (reproduction du cas inc-vide de phase4-hard) : 1 fusion annulée
    comptée, 3 singletons, singletons annulés marqués garde-fou.
  - T23g : un groupe normal est conservé intact par le filtre (0 annulation).
- `test_exploratoire.dart` : **8 OK, 2 LIMITES confirmées** (E4 et E7,
  préexistantes, inchangées) ; nouveau cas E9 OK : deux textes vides au
  même lieu et au même temps ne fusionnent pas et sont marqués garde-fou.
- `dart analyze` sur les quatre fichiers modifiés : **No issues found**.
  (Les 7 problèmes mongo_dart connus du dépôt, sur d'autres fichiers,
  ne concernent pas ce patch et n'ont pas été re-mesurés ici.)

## 4. Périmètre exact et ce que le garde-fou NE résout pas

Il résout un seul échec, précisément : la fusion sans preuve de
contenu. Il ne résout pas :
- le lieu inconnu (coordonnées absentes, aucun lieu dans le texte) ;
- le temps inconnu (t absent) ;
- les contradictions (états résolu contre en cours, gravités ou
  catégories contradictoires) ;
- les textes quasi identiques pour des incidents distincts (temps
  éloigné, détail nord/sud) ;
- les signalements multi-problèmes (un seul texte, deux incidents) ;
- les textes courts mais trompeurs (2 caractères ou plus, abréviations
  ambiguës, fautes) ;
- la qualité d'une fusion entre deux textes normaux.

## 5. Pourquoi l'incertitude Meta seule ne suffisait pas

Le cas inc-vide de phase4-hard est la preuve : le modèle avait fusionné
deux textes vides avec une incertitude de 1,0, tout en écrivant dans sa
propre justification qu'il n'y avait « aucune preuve positive ».
L'incertitude était donc maximale ET la fusion a quand même eu lieu :
l'incertitude décrit un doute, elle n'empêche rien. Phase4-misleading
confirme le problème dans l'autre sens : la fausse fusion multi-probleme
a une incertitude de 0,2, plus basse que la séparation correcte
distinct-detail (0,4). Aucun seuil d'incertitude ne sépare le bon du
mauvais sur ces cas. Seule une règle déterministe, appliquée après la
sortie du modèle et indépendante de son incertitude, garantit que la
fusion n'aura pas lieu. C'est ce que fait ce patch, pour le seul cas du
contenu insuffisant.

## 6. Limites du patch lui-même

- Le verrou inter-processus et la persistance MongoDB ne sont pas testés
  dans cette VM (MongoDB indisponible ici) : le patch ne touche ni au
  verrou ni à la persistance, mais son comportement en serveur réel
  (endpoints `/api/meta/*`, persistance `metaGroups`) reste à vérifier
  sur la machine Windows, comme toute la preuve serveur bout en bout.
- Le seuil « moins de 2 caractères » est une convention, pas une vérité
  mesurée : un texte de 2 caractères passe, un texte d'un mot ambigu
  passe aussi. Il faudra le confronter à des signalements réels avant
  de le durcir.
- Le patch ne couvre pas la couche synonymes Python de phase4-hard, qui
  est un comparateur d'analyse, pas le code du serveur : dans le serveur,
  la voie synonymes n'existe pas, seules les voies classique et Meta
  sont concernées, et les deux sont couvertes.
- Ce patch n'est pas poussé : il attend la vérification et le push
  manuel par l'utilisateur, comme le patch E4 + verrou avant lui.
