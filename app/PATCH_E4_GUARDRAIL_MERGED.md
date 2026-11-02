# Fusion E4 + garde-fou — notes de fusion (locale, NON poussée)

## Pourquoi une fusion était nécessaire

Le patch garde-fou seul (`~/workspace/cityresolve/patch-guardrail-app/`) a été
construit à partir du miroir pré-E4 (`~/workspace/cityresolve/repo-mirror/`).
Le pousser tel quel aurait **régressé E4**, de trois façons vérifiées par diff :

1. `lib/grouping.dart` : la branche `ambiguousPairs` E4 (texte similaire,
   temps proche, distance > 2 × distMax → doublon distant signalé à vérifier,
   **non fusionné**) avait disparu.
2. `lib/server_lock.dart` + `bin/server.dart` : le verrou mono-instance E4
   avait disparu (import supprimé, acquisition supprimée dans `server.dart`).
3. `test/test_all.dart` : les tests garde-fou avaient **écrasé** les tests
   verrou en reprenant leurs noms T23a–g.
4. `test/test_exploratoire.dart` : l'idéal E4 était redevenu « 1 incident »
   (fusion forcée), donc E4 redevenait une limite au lieu d'un OK signalé.

Cette fusion corrige les quatre points. **Rien n'a été poussé sur GitHub,
rien n'a été envoyé à ChatGPT, aucune clé n'a été lue ni copiée.**
Aucun Q, aucun seuil, aucun protocole n'a été touché.

## Base et sources

- Base préservée : `~/workspace/cityresolve/push-staging-1/app/` = version E4
  déjà sur main (grouping avec `ambiguousPairs` doublon distant,
  `server_lock.dart`, `server.dart` avec verrou, `test_all.dart` avec T23
  verrou, `test_exploratoire.dart` avec E4 = 2 incidents séparés ET paire
  ambiguë présente).
- Apports fusionnés, depuis `~/workspace/cityresolve/patch-guardrail-app/app/` :
  - `lib/grouping.dart` : garde-fou contenu insuffisant uniquement.
  - `lib/meta_connector.dart` : filtre post-modèle uniquement (ce fichier
    n'avait pas été modifié par E4 ; reprise directe vérifiée : le seul diff
    par rapport au miroir est l'import de `grouping.dart` et l'appel à
    `applyContentGuardrail` dans `proposeMatchingWithMeta`).
  - `test/test_all.dart` : bloc garde-fou uniquement, renommé (voir ci-dessous).
  - `test/test_exploratoire.dart` : bloc E9 uniquement, repris verbatim.

## Contenu de ce dossier

- `app/lib/grouping.dart` — E4 + garde-fou.
- `app/lib/meta_connector.dart` — version garde-fou (identique au fichier
  garde-fou, byte pour byte vérifié par `diff -q`).
- `app/lib/server_lock.dart` — version E4 (identique, vérifié par `diff -q`).
- `app/bin/server.dart` — version E4 avec verrou (identique, vérifié par `diff -q`).
- `app/test/test_all.dart` — verrou T23 conservé + garde-fou renommé T24.
- `app/test/test_exploratoire.dart` — idéal E4 conservé + cas E9.
- `app/PATCH_GUARDRAIL_NOTES.md` — notes garde-fou d'origine, reprises.

## Détail de la fusion dans grouping.dart

Vérifié par diff dans les deux sens :

- Fusionné vs E4 : **seulement** trois ajouts garde-fou, aucun autre changement :
  1. `hasInsufficientContent`, `guardrailReason`, `applyContentGuardrail`
     (texte insuffisant = moins de 2 caractères alphanumériques après
     minuscules ; filtre post-modèle/post-classique qui découpe tout groupe
     contenant un contenu insuffisant en singletons marqués, et compte les
     fusions annulées dans `cancelledMerges`).
  2. Saut de paire dans `groupReports` : un contenu insuffisant ne fusionne
     jamais, quelle que soit la distance, le temps ou la similarité.
  3. Raison singleton : un singleton à contenu insuffisant porte
     `guardrailReason` dans ses raisons d'incertitude.
- Fusionné vs garde-fou : **seulement** la restauration de la branche E4
  dans `ambiguousPairs` (le `else if` distance > 2 × distMax avec la raison
  « doublon distant à vérifier, non fusionné »).

## Renommages des tests (collision T23 résolue)

Les tests verrou E4 gardent leurs noms d'origine, car ils sont déjà sur main :

- T23a premier serveur acquiert le verrou, T23b second serveur refusé,
  T23c verrou libéré puis réacquis.

Les tests garde-fou, qui s'appelaient aussi T23a–g dans le patch garde-fou
seul, sont renommés en **T24** (section 24, après la section 23 verrou) :

- T23a → T24a (deux textes vides ne fusionnent pas)
- T23a-bis → T24a-bis (singletons vides marqués garde-fou)
- T23b → T24b (vide contre non vide ne fusionne pas)
- T23c → T24c (un seul caractère ne fusionne pas)
- T23d → T24d (ponctuation/espaces seuls ne fusionnent pas)
- T23e → T24e (texte normal non affecté)
- T23f → T24f (trois vérifications : une fusion annulée comptée,
  fusion annulée → 3 singletons, singletons annulés marqués garde-fou)
- T23g → T24g (groupe normal conservé)

Total garde-fou : 10 vérifications `check()` (T24a compte double avec
T24a-bis, T24f compte triple), d'où le total attendu ci-dessous.
Aucun autre T23 ne subsiste dans le bloc garde-fou (vérifié par grep :
les seuls T23 restants dans le fichier fusionné sont les trois tests verrou).

## Exploratoire : E4 conservé, E9 ajouté

- E4 gardé tel que sur main : « contradiction géographique signalée
  (séparation + alerte) », idéal = 2 incidents séparés ET paire ambiguë
  présente. **E4 ne redevient pas une limite.**
- E9 ajouté verbatim depuis le patch garde-fou : deux textes vides au même
  lieu et au même temps ne fusionnent pas, singletons marqués garde-fou.

## Vérifications exécutées (chiffres réels, non arrondis)

Le dossier fusionné ne contient que les fichiers modifiés, pas l'application
complète : les tests ne peuvent pas tourner seuls dans ce dossier (imports
manquants : optimizer, scenarios, etc.). La vérification a donc été faite
en superposant les fichiers fusionnés sur une copie complète de
l'application garde-fou dans `/tmp/merge-test/app` (copie jetable, aucune
modification des sources E4 ni garde-fou), puis en lançant le SDK Dart de
`~/workspace/cityresolve/dart-sdk` :

```text
cd /tmp/merge-test/app
~/workspace/cityresolve/dart-sdk/bin/dart test/test_all.dart
~/workspace/cityresolve/dart-sdk/bin/dart test/test_exploratoire.dart
~/workspace/cityresolve/dart-sdk/bin/dart analyze lib/grouping.dart lib/meta_connector.dart lib/server_lock.dart bin/server.dart test/test_all.dart test/test_exploratoire.dart
```

Résultats :

- `dart test/test_all.dart` : **85 PASS, 0 FAIL**
  (72 d'origine + 3 verrou T23 + 10 garde-fou T24 ; la ligne finale
  imprimée est `== 85 PASS, 0 FAIL ==`).
- `dart test/test_exploratoire.dart` : **9 OK, 1 LIMITE (E7 seule)**
  (E1, E2, E3a, E3b, E4, E5, E6, E8, E9 OK ; E7 falaise budget, inchangée).
  La ligne finale est `== EXPLORATOIRE : 9 OK, 1 LIMITE(S) CONFIRMEE(S) ==`.
  E4 passe en OK avec 2 incidents et la paire ambiguë
  « texte similaire (Jaccard 1.00) mais distance 6505 m […] doublon distant
  à vérifier, non fusionné ».
- `dart analyze` sur les six fichiers modifiés : **No issues found!**
- Grep explicite dans le grouping fusionné : branche `ambiguousPairs` E4
  présente, `hasInsufficientContent` présent, `applyContentGuardrail`
  présent. Grep dans `meta_connector.dart` : `applyContentGuardrail` appelé
  dans `proposeMatchingWithMeta`.
- Recherche de secrets dans le dossier fusionné : aucune valeur de clé
  (seuls des noms de variables / la construction d'en-tête Bearer du code
  préexistant, sans valeur littérale).

## Ce qui reste à faire par le parent (hors périmètre de cette mission)

Cette mission interdisait tout push : **aucun push n'a été fait**.
Le parent doit, après sa propre vérification, copier ces fichiers fusionnés
à la place des fichiers correspondants dans le projet Windows / le dépôt,
puis pousser sur main. Attention : ne pas pousser le dossier garde-fou seul
ni le dossier E4 seul après cette fusion — seul l'ensemble fusionné
contient les deux comportements sans régression.

Limites connues, inchangées par cette fusion (voir les notes garde-fou
d'origine) : le garde-fou ne vise que l'absence de contenu (un texte de
2 caractères ou plus passe, même vide de sens, ex. « ab ») ; il ne résout
ni le lieu inconnu, ni le temps inconnu, ni les contradictions.
