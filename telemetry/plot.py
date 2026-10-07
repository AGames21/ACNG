"""Create a static evidence figure from real captured samples (matplotlib optional)."""
import argparse
import json
from pathlib import Path


def plot(path, output):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    rows=[json.loads(line) for line in Path(path).read_text(encoding="utf-8").splitlines() if line.strip()]
    if len(rows)<2:
        raise ValueError("Need at least two real samples")
    if len({(r.get('vehicle_id'),r.get('generation')) for r in rows}) != 1:
        raise ValueError("Split at reset/vehicle changes before plotting")
    t=[r['sim_time_s'] for r in rows]
    fig,axes=plt.subplots(3,1,figsize=(10,8),sharex=True,layout="constrained")
    axes[0].plot(t,[r['speed_m_s']/0.44704 for r in rows],color='#246dad',label='Vehicle speed')
    axes[0].set_ylabel('Speed (mph)')
    axes[0].axhline(60,color='#8292a2',linewidth=0.8,linestyle='--')
    axes[0].axhline(100,color='#8292a2',linewidth=0.8,linestyle='--')
    axes[0].set_title('ACNG B001 stock ETK K-Series pilot — master OFF')
    axes[1].plot(t,[r.get('throttle',float('nan')) for r in rows],label='Throttle',color='#158553')
    axes[1].plot(t,[r.get('brake',float('nan')) for r in rows],label='Brake',color='#bd463a')
    axes[1].set_ylabel('Control (0–1)')
    axes[1].legend(loc='upper right')
    colors={'FL':'#246dad','FR':'#229b9d','RL':'#c47725','RR':'#b35e9b'}
    for name,color in colors.items():
        values=[next((w.get('load_raw_n',float('nan')) for w in r.get('wheels',[]) if w.get('name')==name),float('nan')) for r in rows]
        axes[2].plot(t,values,label=name,color=color,linewidth=1)
    axes[2].set_ylabel('Wheel raw load (N)')
    axes[2].set_xlabel('Simulation time since capture start (s)')
    axes[2].legend(ncol=4,loc='upper right')
    for ax in axes: ax.grid(alpha=0.2)
    fig.suptitle('Single pilot; automatic arcade acceleration / realistic braking. Not an AC comparison.',fontsize=9)
    output=Path(output)
    output.parent.mkdir(parents=True,exist_ok=True)
    fig.savefig(output,dpi=150)
    plt.close(fig)


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('input',type=Path)
    p.add_argument('output',type=Path)
    a=p.parse_args()
    plot(a.input,a.output)
