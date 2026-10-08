# GUI001 freeroam control app

BeamNG 0.39.4, isolated West Coast USA, stock ETK K-Series. No AI spawning or driving inputs. **12/12 native checks passed:** startup OFF; real master click loads native heat/wear; real Advanced wear checkbox; FFB switch; strength slider; ABS selector; Factory restore; telemetry stream; master OFF stops every active driving module and UDP stream; ON retains custom choices; preferences save; preferences survive native core unload/reload with master/telemetry OFF.

124 Python tests and existing Node suites pass. Screenshot review confirms a compact master card, Tires/Assists/Wheel/Debug tabs and readable controls. First native run found a test-helper concatenation error; second found an incorrect filesystem method. Corrected to BeamNG's actual directoryCreate API and atomic JSON writes; final complete fresh-profile rerun passed. Telemetry remains loaded but its socket closes on OFF, verified through its new read-only status.

Native screenshots are retained in the private test profile; not bundled with the mod. Full game-process preference restart, physical mouse/drag interaction, real-wheel feel and broader driving/model compatibility remain untested. Native DOM click/input/change paths were exercised, not physical mouse inputs.
