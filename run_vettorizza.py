"""Punto di avvio usato da PyInstaller per creare Vettorizza.exe.

``Vettorizza.exe cli immagine.png -o cartella`` esegue la conversione senza finestra.
"""

import sys

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "cli":
        from vettorizza.cli import main as cli_main

        sys.exit(cli_main(sys.argv[2:]))

    from vettorizza.gui.app import main

    sys.exit(main())
