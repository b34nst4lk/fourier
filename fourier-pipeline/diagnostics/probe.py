import json, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
P=[p for p in json.load(open("/opt/workspace/tmp/fourier-svg/violin-snowman/snowman-v2-dots.json"))]
body=[p for i,p in enumerate(P) if not (10<=i<=19 or 31<=i<=40)]
def panel(ax,dots,title,lw,dash=True,ms=0,filled=False,idx=None):
    Q=np.array(dots+[dots[0]],float)
    if filled: ax.fill(Q[:,0],Q[:,1],color="#ededed",ec="none")
    ax.plot(Q[:,0],Q[:,1],ls=(0,(3,2.6)) if dash else "-",lw=lw,color="black",solid_capstyle="round")
    if ms: ax.scatter([p[0] for p in dots],[p[1] for p in dots],s=ms,color="crimson",zorder=3)
    if idx:
        for i,(x,y) in enumerate(dots):
            if i in idx: ax.annotate(str(i+1),(x,y),fontsize=5,color="blue")
    ax.set_title(title,fontsize=8); ax.set_xlim(0,100); ax.set_ylim(100,0)
    ax.set_aspect("equal"); ax.set_xticks([]); ax.set_yticks([])
    for s in ax.spines.values(): s.set_visible(False)
fig=plt.figure(figsize=(10.2,3.4),dpi=100)
panel(fig.add_axes([0.005,0.03,0.32,0.88]),P,"v2 draft 44 as the toy draws it (340px)",1.6,ms=4)
panel(fig.add_axes([0.34,0.03,0.32,0.88]),body,"body only, arms removed, n=%d"%len(body),1.6,ms=4)
panel(fig.add_axes([0.67,0.03,0.32,0.88]),P,"enlarged, nodes 10/21 + 11..20",0.9,dash=False,ms=8,idx={9,20,10,19})
fig.savefig("probe-v2.png"); print("ok", len(P), len(body))
