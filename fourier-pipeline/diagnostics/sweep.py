import json, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import make_branch as mb

CAND = {
 "E1 t20 L19 f.62 a20 d7.5": dict(L=19.0, theta=20, half_root=1.5, fork_at=0.62, fork_angle=20, fork_len=7.5, bend=0.10),
 "E2 t24 L19 f.60 a24 d8.0": dict(L=19.0, theta=24, half_root=1.5, fork_at=0.60, fork_angle=24, fork_len=8.0, bend=0.10),
 "E3 t28 L17 f.55 a26 d7.0": dict(L=17.0, theta=28, half_root=1.5, fork_at=0.55, fork_angle=26, fork_len=7.0, bend=0.08),
 "E4 t20 L21 f.66 a18 d8.5": dict(L=21.0, theta=20, half_root=1.5, fork_at=0.66, fork_angle=18, fork_len=8.5, bend=0.10),
 "E5 t26 L20 f.58 a30 d9.0": dict(L=20.0, theta=26, half_root=1.5, fork_at=0.58, fork_angle=30, fork_len=9.0, bend=0.10),
 "E6 t22 L18 f.70 a22 d6.5": dict(L=18.0, theta=22, half_root=1.5, fork_at=0.70, fork_angle=22, fork_len=6.5, bend=0.09),
}
PX=340
fig,axes=plt.subplots(2,3,figsize=(3*(PX+16)/100,2*(PX+34)/100),dpi=100)
ok={}
for ax,(name,kw) in zip(axes.ravel(),CAND.items()):
    d=mb.build(**kw); r=mb.check(d,quiet=True)
    ok[name]=(d,r)
    P=np.array(d)
    ax.plot(np.append(P[:,0],P[0,0]),np.append(P[:,1],P[0,1]),ls=(0,(3,2)),lw=1.6,color="black")
    ax.set_xlim(0,100); ax.set_ylim(100,0); ax.set_aspect("equal"); ax.axis("off")
    ax.set_title(f"{name} n={r['n']} adj={r['min_adj']:.2f} int={r['hits']}",fontsize=7.5)
    if r["hits"]==0: json.dump(d,open(name.split()[0]+"-dots.json","w"))
fig.subplots_adjust(0.004,0.02,0.996,0.95,0.01,0.06)
fig.savefig("sweep-fork.png")
print("saved")
for n,(d,r) in ok.items(): print(r["row"])
