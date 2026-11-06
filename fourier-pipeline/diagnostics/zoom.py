import json, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
V2="/opt/workspace/tmp/fourier-svg/violin-snowman/snowman-v2-dots.json"
panels=[("v2","../violin-snowman/snowman-v2-dots.json"),("brA","brA-dots.json"),("brB","brB-dots.json"),("brC","brC-dots.json")]
fig,axes=plt.subplots(2,4,figsize=(14,7),dpi=100)
for j,(t,f) in enumerate(panels):
    P=np.array(json.load(open(f)))
    for i,(xl,yl,xr,yr) in enumerate([(-20,-14,4,-8),(0,0,0,0)]):
        ax=axes[i,j]
        ax.plot(np.append(P[:,0],P[0,0]),np.append(P[:,1],P[0,1]),ls=(0,(3,2)),lw=1.6,color="black")
        ax.set_aspect("equal")
        ax.axis("off")
        if i==0:
            ax.set_xlim(8,42); ax.set_ylim(56,22)
        else:
            ax.set_xlim(0,100); ax.set_ylim(100,0)
        ax.set_title(f"{t} "+("arm detail" if i==0 else "full"),fontsize=9)
fig.tight_layout()
fig.savefig("zoom-arms.png")
print("ok")
