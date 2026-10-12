1. Qué es HARPY

Prototipo de acción 3D en Godot 4.7.2: un héroe con alas que vuela como
Superman/Linterna Verde, pelea cuerpo a cuerpo, tira plumas proyectil,
agarra cosas con las garras de los pies en pleno vuelo y golpea con ráfagas
de viento. Todo corre sobre el maniquí humanoide de Godot (el rig
Standard) retargeteado por código con animaciones del paquete
Universal Animation Library (UAL1/UAL2 de Quaternius).

Filosofía de la sesión de trabajo: prototipo rápido, prueba en cancha,
ajuste en vivo (Remote + perillas), y si algo no convence → fuera sin drama
pero guardando las lecciones.
2. Sistemas activos (qué hay y por qué está así)
2.1 Vuelo héroe 360 ⭐ (el corazón)

    Cómo vuela: la cámara dirige, el cuerpo le sigue SIEMPRE. Space sube,
    C pica, Shift = boost. La demanda de empuje es UN número heurístico
    compartido entre física y animación: la animación muestra exactamente lo
    que la física está haciendo.
    La pose: brazo derecho estirado al frente (superman), izquierdo
    pegado, piernas rectas con puntas extendidas (VueloHeroe, generado por
    código). Crucero lento = Planeo (alas quietas), picada = PosePicado,
    bajada sin dirección = CaidaLibre.
    Por qué: probamos contra referencias reales (Web Wings de Spider-Man 2,
    wingsuit de Just Cause, el Vulture, el hipogrifo de Hogwarts): lo que se
    siente bien es inclinarse hacia donde vas y que la animación responda
    a la intención. El modelo "héroe" lo eligió el usuario entre variantes
    («me encantó») y se itera sobre él.
    Aleteo: el overlay de aleteo de brazos original fue reemplazado por la
    pose héroe… pero quedó un aleteo residual en la trepada que el usuario
    APROBÓ («me gusta que aletee») — se queda. El clip AleteoAlas vive en el
    cajón del loader por si acaso.

2.2 Combate cuerpo a cuerpo

    Combo de 4 golpes (Jab → Cross → Kick → Uppercut) con anims UAL
    retargeteadas, detección por esfera delante del jugador, knockback y
    daño sobre los maniquíes de práctica.
    Los golpes de melee llevan el giro del Root horneado afuera
    (CLIPS_SIN_GIRO_ROOT): el uppercut giraba al personaje entero — la
    orientación la maneja nuestro código, no el clip.

2.3 Guardia de alas (Q, mantener)

    100 % procedural: brazos cruzados en X al pecho, regenerada en vivo.
    Cinco perillas ajustables mientras jugás (Remote → Inspector): el
    patrón "config en vivo" nació acá y se convirtió en estándar del proyecto.
    Los valores finales NO se corrigen: están aprobados a ojo.

2.4 Plumas proyectil + apuntado OTS

    RMB = apuntar (mira al hombro, cuerpo girando con la cámara), LMB dispara
    ráfagas hacia el punto de mira. Daño real sobre maniquíes.
    El lado del disparo se LEE del clip (se cuentan pistas de brazos
    izquierdo/derecho) — no se adivina.
    El proyectil cobra el daño él mismo (_impactar): la lección de las
    plumas que no dañaban (collision layer 0 + queue_free mudo).

2.5 Garras de los pies (E+G, solo volando)

    Pies, no manos: la presa cuelga DEBAJO del cuerpo (como un águila).
    Solo agarre volando; al aterrizar se suelta; lanzar = patada procedural
    (PatadaGarra) con impulso hacia donde mirás.
    v1 aprobada con esta regla de oro: los detalles físicos del agarre pueden
    mejorar después, la IDENTIDAD (pies, debajo, solo aire) no se discute.

2.6 Palmazo de viento (V) 🆕

    Juntada de palmas → ráfaga direccional: cono de 70° hacia donde
    mirás con pitch incluido (mirás al piso, barre el piso), que empuja
    maniquíes y props y los eleva (0.6 de componente vertical). Daño
    chico, empuje grande: «el aleteo convertido en arma».
    Gesto: secuencia Push_Enter → Push → Push_Exit de UAL1, recortada a
    solo torso+brazos (piernas libres), concatenada en un clip único
    (PalmazoPush) y reproducida a 2.5× por el mismo canal del melee.
    Primera versión por el overlay de brazos no se veía → camino probado
    primero, siempre.
    Cooldown 2.5 s, alcance 4.5 m. Todo ajustable en vivo.

2.7 Cámara y efectos

    La cámara de tercera persona es del USUARIO (dueña del script):
    FOV por velocidad, OTS, pad. Ningún script del proyecto la pisa.
    EfectosCamara (nuevo): screen shake por trauma (trauma², se
    disipa solo), golpes de FOV por evento y FOV abierto en picada.
        Arquitectura clave: corre al final del frame (process_priority) y
        usa préstamo-y-devolución (aplica su rotación/FOV encima de lo que
        la cámara escribió y lo devuelve antes del siguiente) → nunca pelea con
        el script dueño ni acumula error.
        Eventos automáticos por animación/velocidad: golpes del combo, palmazo,
        backflip, aterrizajes duros, picada. Cero acoples: si mañana hay un
        clip nuevo, se agrega una línea en una tabla.
    Aterrizaje épico: caída rápida → BackFlip de recuperación (referencia
    Arkham); el FOV de picada vendé con el boost.

2.8 Animaciones: el loader único

    ual2_animation_loader.gd es el corazón técnico: carga clips desde los
    GLB de UAL (source y standard), los retargetea por código al
    esqueleto del maniquí, genera los procedurales (Planeo, PosePicado,
    CaidaLibre, VueloHeroe, PalmazoPush, GuardiaAlas, PatadaGarra, AleteoAlas)
    y deja todo en la biblioteca UAL2 con un overlay de brazos.
    Retarget por código, no BoneMaps de import: control total y
    portabilidad (el banco de animaciones empaqueta lo mismo para re-uso).
    Espejado de golpes por código (intercambio Left↔Right + reflexión sobre
    un eje): Godot no tiene espejo nativo de animaciones (propuesta 8478).

2.9 Maniquíes de práctica

    RigidBody con damping, invulnerabilidad al estar congelados, daño por
    impacto (velocidad previa), barras y etiquetas de daño, colapso y respawn.
    SON contenido pedido (prototipo sin enemigos: los maniquíes son el campo
    de pruebas de todo).

3. Lo que quisimos agregar… y sacamos (con el por qué)

Esta sección es la más valiosa: cada descarte costó horas y dejó aprendizaje.
3.1 Root motion — DESCARTADO

Queríamos que la caminata moviera al personaje con las animaciones.
Descartado porque complicaba el feel y el control directo de velocidad era
más estable para un héroe ágil. No reintentar sin pedido nuevo.
3.2 Percharse en bordes — DESCARTADO (prototipado completo v1+v2)

Posar sentado en bordes con salidas por Space/E/F y flip de despegue.
Andaba, pero el usuario decidió: «mejor olvidemos y borremos todo esto de
la esquina, trabajemos puliendo lo que ya tenemos». Revertido por completo.
Lecciones rescatadas: detección del vacío por raycast (el lado sin
choque es afuera) y _recortar_clip (recortar animaciones por código).
3.3 Free look al volar — DESCARTADO

Apuntar volando dirigiendo el vuelo por separado del cuerpo. Descartado por
el usuario («volvamos a como antes»): apuntar dirige el vuelo y el cuerpo
siempre sigue la cámara. Regla de oro del vuelo.
3.4 Térmicas y corrientes de aire — RECHAZADAS

Como fuente de altura/velocidad. El usuario fue claro: «el personaje
controla el viento» (no al revés). Coherente con la identidad del héroe.
3.5 La migración al modelo Mixamo (FBX) — DESCARTADA (la saga completa)

Objetivo: reemplazar el maniquí por un FBX de Mixamo. Probamos tres
arquitecturas de migración de esqueleto:

    Retarget de pistas (reescribir pistas con nombres mapeados): poses
    rotas — los quaternions locales dependen del rest de CADA rig.
    Espejo runtime (el maniquí "marionetista" baila y el modelo copia su
    pose global cada frame): funcionó de verdad (el modelo animó), pero la
    cadena nodo→esqueleto→frame era frágil y cada fix revelaba otro
    desalineo (escala en cm, giro +Z, origen fuera de los pies, hitbox
    desencajada, el AABB de skinned meshes que MIENTE al medir el piso).
    Bake al cargar (hornear los clips muestreados al esqueleto destino):
    escribió pistas correctas pero el modelo no se movía (causa nunca hallada;
    el autotest con veredicto lo detectó y activó el espejo de emergencia).

Tras varias rondas el usuario cortó: «solo quiero cambiar el maniquí por el
nuevo modelo» → volvimos al maniquí y se archivó todo el código.
Lecciones que quedan guardadas (en INVENTARIO_Y_ESTADO.md): el espejo
verbatim SÍ anima entre rigs distintos; el piso se mide por huesos, no por
AABB; Mixamo mira a +Z y Godot a −Z; nodo del modelo SIEMPRE en identity;
el autotest (reproducir + medir + veredicto) es un patrón de oro.
Si algún día se retoma: el auto-rigger de Mixamo deja cualquier GLB en la
misma pipeline de huesos mixamorig.
3.6 Aura de vuelo — DESCARTADA

Partículas que subían por el cuerpo + luz, siguiendo al jugador (estilo
Linterna Verde). Cuatro rondas de fixes (enum en el material correcto,
re-parenteo automático, coordenadas locales, modo prueba) — el diagnóstico
decía que todo funcionaba, pero no convenció visualmente y el usuario la
bajó: «mejor eliminamos lo del aura». Fuera, con lecciones: los efectos
"que siguen" deben validar su parent en runtime; su compilador trata los
ternarios con tipos mixtos como ERRORES.
3.7 Aleteo overlay de brazos — REEMPLAZADO (no descartado)

Por la pose héroe. El aleteo residual que quedó en trepada fue aprobado.
4. Decisiones de arquitectura que sobreviven

    Un loader de animaciones, dueño de todo el pipeline: fuentes →
    retarget → procedurales → bibliotecas. Nadie más toca clips.
    Los scripts son dueños de su territorio: la cámara es del usuario;
    el Player delega en el FlightController (update_flight() == true →
    solo move_and_slide); los efectos de cámara aplican ENCIMA sin editar.
    Botón contextual único: LMB en mouse / R2 en pad, un solo botón
    principal que cambia según el contexto (apuntar > presa cargada >
    agarrar > golpe). Los cuatro contextos nunca se pisan.
    Config en vivo siempre: Remote + setters = ajustar jugando. Nada de
    recompilar para probar un número.
    Compilador estricto = estilo blindado: cero ternarios con tipos
    mixtos, tipos explícitos en declaraciones ambiguas, chequeador de
    identificadores después de toda cirugía de código (las declaraciones
    comidas por reverts lo enseñaron a las malas).
    Scripts completos, nunca parches: el archivo entero va al workspace
    y del workspace al editor con Ctrl+A.
    Dive no "de espaldas" (lerp a −PI) y pitch positivo = boca arriba:
    convenciones escritas para no volver a romperlas.

5. Estado y pendientes (el arranque de la próxima etapa)

Aprobado y en el juego: vuelo héroe 360 (con aleteo residual), combo +
guardia, plumas OTS, garras de pies, palmazo de viento, efectos de cámara,
aterrizaje épico, maniquíes de práctica con daño.

Pendiente (roadmap de pulido):

    Sonido — el banco #1: whoosh de plumas y palmazo, impactos de melee,
    viento de picada, aleteo. Lo que menos código y más se siente.
    Banco de animaciones: re-pagar el empaquetador v2 y re-ejecutar
    (un paquete portable con todo el catálogo).
    Input Map: borrar dive_bomb, sumar C a fly_down, L3/R3 al sprint.
    Juice de impacto: hitstop, chispas, screen shake direccional por
    golpe conectado (la base ya está en EfectosCamara.impacto()).
    Circuito con propósito: anillos/ruta que dé razón para volar bien.
    FreeflowCombat: EN PAUSA explícita (bug «solo rodillazo» abierto).

6. Referencias de diseño que nos guiaron

    Spider-Man 2 (Web Wings): dive→velocidad→altura; stick adelante pica.
    Just Cause (wingsuit): la energía siempre se gasta — «planear se
    siente ganado».
    Hogwarts Legacy (hipogrifo): la animación responde a la intención
    (subir aleteando, bajar encogiendo alas).
    El Vulture (Marvel): alas bajo los brazos, dirige con el cuerpo entero.
    Falcon (previz de Winter Soldier, 14 meses): el aterrizaje épico vale
    el esfuerzo — de ahí el BackFlip de recuperación.
