# -*- coding: utf-8 -*-
import sys
sys.path.insert(0, "D:/roguedemo/design/phase2/numeric-sim")
import corebound_sim_v03 as sv, corebound_sim_v08_salvage as v8
for km in ("tier","flat"):
    for path in ("A","B"):
        cfg = v8.cfg_of(path, kr_mode=km)
        st = v8.final_state(path, cfg, waves=20, salvage_on=False)
        info = st["info"]
        print('MODE=%s PATH=%s TOTAL=%r' % (km, path, st["dps"]))
        print('   subtotal=%r aoe=%r cf=%r aux=%r' % (info["subtotal"], info["aoe"], info["crossfire"], info["aux"]))
        for k,t in enumerate(st["player"].towers):
            pt = info["per_tower"][k]
            print('   #%d %s h=%d L=%r base=%r stack=%r res=%r foc=%r allin=%r cov=%r dps=%r E=%r kappa=%r kr=%r'
                  % (k,t.ctype,t.h,info["L"][k],pt["base"],pt["stack"],pt["res"],pt["focus"],pt["allin"],pt["cov"],pt["dps"],info["E"][k],info["kappa"][k],info["kr"][k]))
print("GEO6 cov repr:")
for tn in ("Arrow","Cannon","Frost"):
    for s in range(6):
        print('   %s %d %r' % (tn, s, sv.GEO6.cov[(s,tn)]))
print("softcap check 101:", repr(sv.softcap_pow(101,1.10,100,1.03)), repr((1.10**100)*1.03))
print("1.05**134 =", repr(1.05**134), " 1.045**9 =", repr(1.045**9))
