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
```

Поддерживаются `.glb`, `.gltf`, `.tscn`, `.scn`.

## Требования к модели постройки

- Начало координат — в центре основания, ось +Z смотрит на двор (фасад).
- Масштаб в метрах: клетка боя равна 1.5 м, рост героя — 1.8 м.
- Препятствие строится автоматически по габаритам модели.

## Требования к модели персонажа

Чтобы заработали существующие анимации, в модели должны быть узлы с именами:
`Torso`, `Head`, `ShoulderL`, `ShoulderR`, `ForearmL`, `ForearmR`, `HipL`,
`HipR`, `ShinL`, `ShinR`, `Weapon`. Если модель приходит со своим
`AnimationPlayer`, лучше вызывать его клипы — правка в `ActorAnimator`.

## Проверка

```bash
godot --headless --path . --script res://tools/check_assets.gd
```

Печатает, какие модели найдены, а какие строятся процедурно.
