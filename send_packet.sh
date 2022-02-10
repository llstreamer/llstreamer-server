#!/bin/bash
printf '00''00000001''00000000''0001''ff' | xxd -r -p | nc localhost 9009
