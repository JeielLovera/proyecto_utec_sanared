# Slide — Comparación de Alternativas de Arquitectura EMPI
### EMPI Centralizado (Alt. 1) vs. Multicloud Concordante (Alt. 3 Mejorada)

> **Uso:** cuadro para un único slide ejecutivo. Pegar en PowerPoint / Google Slides / Marp.
> Fuente de detalle: `Comparativo_Alt1_Hito2_vs_Alt3Mejorada_Hito3.md`.

---

## Cuadro comparativo (versión slide)

| Criterio de decisión | 🔵 Alt. 1 — Centralizada AWS | 🟢 Alt. 3 Mejorada — Multicloud Concordante |
|---|---|---|
| **Estrategia de nube** | 1 nube (AWS) — simple | 3 nubes por afinidad de negocio ✔ |
| **Escalabilidad de matching** | Sin índice dedicado | Índice OpenSearch a millones de registros ✔ |
| **Dependencia de proveedor** | Alta (atado a AWS) | Baja — bus neutral, portable ✔ |
| **Seguridad / perímetro** | Perímetro único | Por dirección (WAF / mTLS / APIM) ✔ |
| **Disponibilidad** | Multi-AZ, 99.9% ✔ | Multi-AZ + bus factor 3, 99.9% ✔ |
| **Costo y operación** | Consolidado y previsible ✔ | Distribuido + egreso cross-cloud |
| **Auditoría y trazabilidad** | Escritura secundaria | Nativa e inmutable por eventos ✔ |
| **Complejidad / riesgo de ejecución** | Menor ✔ | Mayor (DDD/CQRS + multicloud) |

---

> **Recomendación: Alternativa 3 Mejorada.** Es la arquitectura que **escala a la volumetría real** de SanaRed
> (matching sobre millones de registros), **evita el lock-in** de proveedor con un bus neutral portable,
> **refuerza la seguridad** con perímetro por dirección de tráfico y aporta **trazabilidad nativa** por eventos —
> aprovechando las **3 nubes por concordancia de dominio**. La Alt. 1 conserva valor solo como **línea base de
> adopción incremental**, sobre el mismo núcleo AWS, sin reescribir el sistema.

---

## Notas para el expositor (no van en el slide)

- **Mensaje central (1 frase):** *"Ambas resuelven la identidad única, pero la Alt. 3 Mejorada es la que escala a la volumetría real, evita el lock-in y aprovecha las 3 nubes de SanaRed por afinidad de negocio — por eso es la solución escogida."*
- **Diferenciales de la Alt. 3M:** escalabilidad de matching (OpenSearch a millones de registros), portabilidad anti-lock-in (bus neutral) y auditoría nativa por eventos. *(La unificación de imágenes inter-sede — GT-04/GSI-08 del Hito 1 — es otra ventaja de la Alt. 3M; se retiró del cuadro por espacio, pero puede mencionarse de viva voz.)*
- **No hay ganador absoluto:** se presentan como continuo evolutivo — empezar simple (Alt. 1), madurar hacia concordante (Alt. 3M); el núcleo AWS es compartido, así que no se reescribe el corazón del sistema.
- **Si preguntan por latencia/observabilidad/disponibilidad:** están cubiertos en el documento comparativo completo; se omiten del slide para no saturarlo (el slide vende la decisión, no el detalle).
