# Модели

Игра ищет здесь готовые модели и подставляет их вместо процедурной геометрии.
Если файла нет — строится процедурная заглушка, всё работает как раньше.

```
assets/models/village/forge.glb       кузница
assets/models/village/training.glb    тренировочный зал
assets/models/village/shop.glb        лавка
assets/models/village/garden.glb      сад
assets/models/village/storage.glb     склад
assets/models/village/descend.glb     спуск в Разлом
assets/models/village/chapel.glb      часовня «Алтарь»

assets/models/actors/hald.glb         герои по id
assets/models/actors/irma.glb
assets/models/actors/vern.glb
assets/models/actors/mara.glb
assets/models/actors/enemy_default.glb

assets/models/props/chest_common.glb    сундук в обычной комнате
assets/models/props/chest_treasure.glb  сундук в сокровищнице
```

Поддерживаются `.glb`, `.gltf`, `.tscn`, `.scn`.

## Требования к модели постройки

- Начало координат — в центре основания, ось +Z смотрит на двор (фасад).
- Масштаб в метрах: клетка боя равна 1.5 м, рост героя — 1.8 м.
- Препятствие строится автоматически по габаритам модели.

## Требования к модели персонажа

Лучший вариант — модель со своим `AnimationPlayer`: `ActorAnimator` сам найдёт
клипы по именам (`Idle`, `Walking_A`, `1H_Melee_Attack_Chop`, `Spellcast_Shoot`,
`Hit_A`, `Death_A`) и будет играть их вместо самодельных твинов.

Если `AnimationPlayer` в модели нет, работают твины по суставам, и тогда в
модели должны быть узлы с именами: `Torso`, `Head`, `ShoulderL`, `ShoulderR`,
`ForearmL`, `ForearmR`, `HipL`, `HipR`, `ShinL`, `ShinR`, `Weapon`.

## Таблица соответствий `aliases.json`

Модель к персонажу привязывается не именем файла, а таблицей — так один набор
моделей обслуживает несколько id, и кит меняется без правки кода:

```json
{
  "hald": "kaykit_heroes/Knight",
  "bone_abbot_scale": 0.78,
  "_folder_scale": {"kaykit_heroes": 0.65}
}
```

- `"<id>"` — путь к модели от `assets/models/` без расширения.
- `"<id>_scale"` — множитель размера для одного персонажа.
- `"<id>_yaw"` — доворот вокруг Y в градусах.
- `"_folder_scale"` / `"_folder_yaw"` — значения по умолчанию для целого кита.

Про `yaw`: «перёд» узла в Godot — это −Z, а модели китов почти всегда смотрят в
+Z, поэтому по умолчанию берётся 180°. Без этого персонаж идёт спиной вперёд и
смотрит в камеру.

Разворот применяется к вложенному узлу, а не к корню: игровой код крутит корень
обычным `rotation.y`, ничего не зная про особенности конкретного кита.

## Что подключено сейчас

| Набор | Лицензия | Что берём |
|---|---|---|
| KayKit Adventurers | CC0, Kay Lousberg | герои: Knight, Rogue, Rogue_Hooded, Mage |
| KayKit Skeletons | CC0, Kay Lousberg | нежить: Warrior, Rogue, Mage, Minion |
| KayKit Dungeon Remastered | CC0, Kay Lousberg | сундуки: обычный и сокровищницы |
| Kenney Castle / Graveyard / Nature / Town | CC0, Kenney | постройки деревни (кит-бэшинг) |

## Проверка

```bash
godot --headless --path . --script res://tools/check_assets.gd
```

Печатает, какие модели найдены, а какие строятся процедурно.
