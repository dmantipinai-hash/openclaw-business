import * as d3 from 'd3';

const COLOR_MAP = {
  entry: '#e1f5fe',
  cron: '#fff3e0',
  agent: '#f3e5f5',
  model: '#e8f5e9',
  tool: '#fff8e1',
  store: '#fce4ec',
  external: '#f5f5f5'
};

const STROKE_MAP = {
  entry: '#01579b',
  cron: '#e65100',
  agent: '#4a148c',
  model: '#1b5e20',
  tool: '#f57f17',
  store: '#880e4f',
  external: '#424242'
};

async function loadScanData() {
  const response = await fetch('../../docs/scan.json');
  if (!response.ok) throw new Error('Failed to load scan.json');
  return await response.json();
}

function initGraph(data) {
  const container = document.getElementById('graph-container');
  const width = 1200;
  const height = 800;

  const svg = d3.select('#graph-container')
    .append('svg')
    .attr('width', width)
    .attr('height', height);

  const g = svg.append('g');

  const zoom = d3.zoom()
    .scaleExtent([0.3, 3])
    .on('zoom', (event) => g.attr('transform', event.transform));

  svg.call(zoom);

  const simulation = d3.forceSimulation(data.graph.nodes)
    .force('link', d3.forceLink(data.graph.edges).id(d => d.id).distance(120))
    .force('charge', d3.forceManyBody().strength(-400))
    .force('center', d3.forceCenter(width / 2, height / 2))
    .force('collision', d3.forceCollide().radius(50));

  const links = g.append('g')
    .selectAll('line')
    .data(data.graph.edges)
    .enter()
    .append('line')
    .attr('class', 'link')
    .attr('stroke', '#999')
    .attr('stroke-width', 1.5);

  const linkLabels = g.append('g')
    .selectAll('text')
    .data(data.graph.edges)
    .enter()
    .append('text')
    .attr('class', 'link-label')
    .attr('text-anchor', 'middle')
    .text(d => d.label || '');

  const nodes = g.append('g')
    .selectAll('.node')
    .data(data.graph.nodes)
    .enter()
    .append('g')
    .attr('class', 'node')
    .call(d3.drag()
      .on('start', dragstarted)
      .on('drag', dragged)
      .on('end', dragended));

  nodes.each(function(d) {
    const node = d3.select(this);
    const kind = d.kind || 'external';
    const fillColor = COLOR_MAP[kind] || '#f5f5f5';
    const strokeColor = STROKE_MAP[kind] || '#424242';

    node.append('rect')
      .attr('width', 140)
      .attr('height', 50)
      .attr('x', -70)
      .attr('y', -25)
      .attr('fill', fillColor)
      .attr('stroke', strokeColor)
      .attr('class', 'node-rect');

    node.append('text')
      .attr('dy', 5)
      .attr('text-anchor', 'middle')
      .text(d.label);
  });

  const tooltip = document.getElementById('tooltip');

  nodes.on('mouseover', function(event, d) {
    const kind = d.kind || 'external';
    const sub = d.sub || '';
    const detail = d.detail || '';
    tooltip.style.display = 'block';
    tooltip.innerHTML = `<strong>${d.label}</strong><br/><em>${kind}</em><br/>${sub}<br/>${detail}`;
    tooltip.style.left = (event.pageX + 15) + 'px';
    tooltip.style.top = (event.pageY + 15) + 'px';
  })
  .on('mousemove', function(event) {
    tooltip.style.left = (event.pageX + 15) + 'px';
    tooltip.style.top = (event.pageY + 15) + 'px';
  })
  .on('mouseout', function() {
    tooltip.style.display = 'none';
  });

  simulation.on('tick', () => {
    links
      .attr('x1', d => d.source.x)
      .attr('y1', d => d.source.y)
      .attr('x2', d => d.target.x)
      .attr('y2', d => d.target.y);

    linkLabels
      .attr('x', d => (d.source.x + d.target.x) / 2)
      .attr('y', d => (d.source.y + d.target.y) / 2);

    nodes.attr('transform', d => `translate(${d.x},${d.y})`);
  });

  function dragstarted(event, d) {
    if (!event.active) simulation.alphaTarget(0.3).restart();
    d.fx = d.x;
    d.fy = d.y;
  }

  function dragged(event, d) {
    d.fx = event.x;
    d.fy = event.y;
  }

  function dragended(event, d) {
    if (!event.active) simulation.alphaTarget(0);
    d.fx = null;
    d.fy = null;
  }

  return data;
}

function renderStats(data) {
  const stats = document.getElementById('stats');
  stats.innerHTML = `
    <h3>Statistics</h3>
    <ul>
      <li><span>Agents:</span> <strong>${data.stats.agents}</strong></li>
      <li><span>Models:</span> <strong>${data.stats.models}</strong></li>
      <li><span>Tools:</span> <strong>${data.stats.tools}</strong></li>
      <li><span>Integrations:</span> <strong>${data.stats.integrations}</strong></li>
    </ul>
  `;
}

function renderLegend() {
  const legend = document.getElementById('legend');
  const items = [
    { kind: 'entry', label: 'Entry Point' },
    { kind: 'cron', label: 'Cron' },
    { kind: 'agent', label: 'Agent' },
    { kind: 'model', label: 'Model' },
    { kind: 'tool', label: 'Tool' },
    { kind: 'store', label: 'Store' },
    { kind: 'external', label: 'External' }
  ];

  legend.innerHTML = items.map(item => `
    <div class="legend-item">
      <div class="legend-color" style="background: ${COLOR_MAP[item.kind]}"></div>
      <span>${item.label}</span>
    </div>
  `).join('');
}

async function main() {
  try {
    const data = await loadScanData();
    renderStats(data);
    renderLegend();
    initGraph(data);
  } catch (error) {
    console.error('Error:', error);
    alert('Failed to load architecture data. Make sure docs/scan.json exists.');
  }
}

main();