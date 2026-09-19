## TP 1: Juego 2D

Este repositorio sirve entrega del trabajo práctico 1 del trayecto de image campus 2025 de Desarrollo de Videojuegos con Godot.

## Como se usa este repositorio

Pueden crearse tranquilamente un repositorio de cero, pero si quieren tener uno con configuración para subir el juego a itch automáticamente, pueden generar un repositorio a partir de este:

https://github.com/user-attachments/assets/dbf1368c-6b99-4b02-bf84-7b63d299d5db


## Como subir para que se pueda jugar en itch automáticamente

### Paso 1

Crear el proyecto en itch

   <img height="300" alt="image" src="https://github.com/user-attachments/assets/289a1dd2-72b3-40af-b76a-81bef6d9212f" />

### Paso 2

Ponerle un título al juego, y configurar el **Kind of project** como HTML

   <img height="600" alt="image" src="https://github.com/user-attachments/assets/12ba7e65-e05a-4106-a8f0-69ce8415a851" />

### Paso 3

Clickear Save & view page

   <img width="631" height="190" alt="image" src="https://github.com/user-attachments/assets/bea9ca55-ddf6-4043-87b3-78b079718dac" />

### Paso 4

Configurar los siguientes secretos en el repositorio (eso es en Settings > Secrets and Variables > Actions, pueden guiarse con el vídeo del principio del README)

   - BUTLER_API_KEY -> lo obtienen aquí: https://itch.io/user/settings/api-keys
   - ITCHIO_GAME -> nombre de su juego
   - ITCHIO_USERNAME -> su usuario de itch

### Paso 5

Hacer un commit y un push al repositorio, eso va a disparar una acción que va a exportar su juego y subirlo a itch:

<img width="1910" height="369" alt="image" src="https://github.com/user-attachments/assets/06312139-8854-4d35-8670-552dda17ff6c" />

### Paso 6

Tras subirlo por primera vez, volver a itch, y marcar la opción This file will be played in the browser

Luego de eso, le dan guardar de nuevo.

<img width="627" height="410" alt="image" src="https://github.com/user-attachments/assets/0c5c671d-248e-457c-963e-9144a240f687" />

### ¡Listo!

Ahora, cada vez que hagan un push al repositorio (a la rama principal: `main`), el juego en itch se va actualizar automáticamente.
