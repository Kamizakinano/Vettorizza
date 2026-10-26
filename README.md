# Vettorizza

Programma per Windows che trasforma un'immagine in:

- **vettoriale** (SVG e DXF in millimetri, un livello per colore) da usare in **Fusion 360**;
- **modello 3D multicolore** (3MF, OBJ con colori, STL per colore) da stampare con
  **Bambu Studio** / AMS.

Carichi la foto di un pupazzetto: Vettorizza toglie lo sfondo, riduce l'immagine a pochi
colori ben separati (uno per filamento), ne ricava i contorni e costruisce il modello 3D,
con **una parte per ogni colore**.

## Cosa fa

| Passo | Dettagli |
|---|---|
| Rimozione sfondo | **AI** (modello ISNet/U2Net, gira in locale e offline dopo il primo download), **classico** (sfondo uniforme, GrabCut) oppure la trasparenza dei PNG. Avvisa se lo sfondo è troppo complesso per il metodo classico. |
| Colori | Da 1 a 16 colori con k-means nello spazio Lab. Si possono usare **i colori dei tuoi filamenti**: ogni regione prende il filamento più vicino e lo slot AMS corrispondente. Le texture vengono appiattite e i dettagli troppo piccoli per essere stampati vengono assorbiti. |
| Modifica | Cambia un colore, unisci due colori, elimina un colore (diventa sfondo), cambia lo slot AMS, alza un singolo colore («Extra»: occhi, bottoni…). Clic sull'immagine per trovare a quale colore appartiene una zona. |
| Vettoriale | Contorni sub-pixel lisci; i colori confinanti condividono lo stesso bordo. |
| 3D – Rilievo a strati | Base sagomata + ogni colore estruso sopra (stile portachiavi / targhetta). |
| 3D – Pupazzetto gonfiato | Superficie bombata (un cerchio diventa una semisfera, braccia e orecchie restano più basse e arrotondate), fondo piatto per stampare senza supporti. |
| Anteprima | Vista 3D ruotabile, con le dimensioni reali in mm. |

Tutte le mesh esportate sono solidi chiusi (watertight), con la base a z = 0.

> **Nota sul "3D da una foto":** da una sola immagine non si può conoscere il retro
> dell'oggetto. Vettorizza crea quindi un modello a **rilievo** o **gonfiato** con il
> fondo piatto (il modo più affidabile per stamparlo a colori), non una ricostruzione
> completa a 360°.

## Installazione su Windows

### Opzione A – Eseguibile già pronto
1. Apri la pagina **Actions** del repository su GitHub, poi l'ultima esecuzione di
   *Build Windows* e scarica l'artefatto **Vettorizza-Windows**
   (oppure la pagina **Releases**, se hai creato un tag `v1.0.0`).
2. Estrai lo zip e avvia `Vettorizza\Vettorizza.exe`.

### Opzione B – Crea l'eseguibile da solo
1. Installa [Python 3.12](https://www.python.org/downloads/) (spunta *Add python.exe to PATH*).
2. Fai doppio clic su `build_windows.bat`.
3. Il programma sarà in `dist\Vettorizza\Vettorizza.exe`.

Per avviarlo senza creare l'exe: doppio clic su `avvia.bat`.

Al primo utilizzo il programma propone di scaricare il modello AI per lo sfondo
(171 MB, una volta sola). Per un PC senza internet, copia il file `.onnx` nella cartella
`models` accanto a `Vettorizza.exe`.

## Come si usa

1. **Apri** un'immagine (o trascinala nella finestra).
2. Scegli il **numero di colori** e, se vuoi, spunta **«Usa i colori dei miei filamenti»**
   (l'ordine dei colori = slot AMS 1, 2, 3…).
3. Imposta la **larghezza** in mm.
4. Controlla le schede *Soggetto*, *Colori*, *Vettoriale*, *Anteprima 3D*.
5. **Esporta**: scegli la cartella e i formati.

### In Bambu Studio
- **3MF**: un oggetto con una parte per colore. Se i filamenti non vengono assegnati da
  soli, seleziona ogni parte nell'elenco *Oggetti* e scegli il filamento (lo slot è
  nella tabella dei colori e nel nome della parte).
- **OBJ**: Bambu Studio 1.9+ apre la finestra per abbinare ogni colore a un filamento.
- **STL**: importali tutti insieme e rispondi *Sì* a «caricare come singolo oggetto con
  più parti?».

### In Fusion 360
- **SVG**: *Inserisci › Inserisci SVG* su uno schizzo (misure già in mm), poi *Estrudi*.
  C'è anche l'opzione per un SVG separato per colore.
- **DXF**: *Inserisci › Inserisci DXF*, un layer per colore più il contorno.
- **Mesh**: *Inserisci › Inserisci mesh* (3MF/OBJ/STL).

## Riga di comando

```bat
Vettorizza.exe cli pupazzetto.jpg -o uscita -n 5 --modo gonfiato --altezza 15
Vettorizza.exe cli logo.png --filamenti FFFFFF,000000,C12E1F --larghezza 60
```

(dal codice sorgente: `python -m vettorizza cli …`; `--help` per tutte le opzioni)

## Per sviluppatori

```bash
pip install -r requirements-dev.txt
python -m pytest          # test
python -m vettorizza      # interfaccia
pyinstaller --noconfirm Vettorizza.spec
```

Struttura: `vettorizza/background.py` (sfondo), `colors.py` (colori), `vectorize.py`
(contorni), `model3d.py` + `mesh.py` (3D), `export_vector.py` / `export_3d.py` (file),
`pipeline.py` (flusso completo), `gui/` (interfaccia PySide6).

I modelli AI per lo sfondo provengono dal progetto
[rembg](https://github.com/danielgatis/rembg) (licenza Apache 2.0).
