import sys

if len(sys.argv) > 1 and sys.argv[1] == "cli":
    from vettorizza.cli import main

    sys.exit(main(sys.argv[2:]))

from vettorizza.gui.app import main

sys.exit(main())
