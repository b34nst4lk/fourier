import json, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
sel=[("E1","E1-dots.json"),("E2","E2-dots.json"),("E4","E4-dots.json"),("E5","E5-dots.json")]
fig,axes=plt.subplots(1,4,figsize=(16,6),dpi=100)
for ax,(t,f) in zip(axes,sel):
    P=np.array(json.load(open(f)))
    ax.plot(np.append(P[:,0],P[0,0]),np.append(P[:,1],P[0,1]),ls=(0,(3,2)),lw=1.9,color="black")
    ax.set_xlim(6,40); ax.set_ylim(58,20); ax.set_aspect("equal"); ax.axis("off")
    ax.set_title(t+" left arm x4",fontsize=10)
fig.tight_layout(); fig.savefig("zoom2.png"); print("ok")
