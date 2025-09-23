# External Data Cache System

The lobby kiosk supports an external JSON data cache system that allows external services to provide dynamic data to the Vue application without requiring rebuilds.

## How It Works

1. **Cache Directory**: `/opt/lobby/cache/` - writable by lobby user and external services
2. **Symlink**: Each app deployment creates `dist/data -> /opt/lobby/cache`
3. **Web Access**: Vue app fetches from `http://localhost:8080/data/*.json`
4. **Static Serving**: The `serve` package serves symlinked files as static content

## Usage

### For External Services

Write JSON files directly to the cache directory:

```bash
# Example: Update player stats
echo '{"players": [{"name": "John", "goals": 5}]}' > /opt/lobby/cache/players.json

# Example: Update schedule data  
curl -o /opt/lobby/cache/schedule.json "https://api.example.com/schedule"
```

### For Vue Application

Fetch data from the cache via HTTP:

```javascript
// Fetch player data
const response = await fetch('/data/players.json');
const players = await response.json();

// Fetch schedule
const schedule = await fetch('/data/schedule.json').then(r => r.json());
```

## Permissions

- Cache directory: `755` (lobby:lobby)
- JSON files: Should be readable by lobby user
- External services need write access to `/opt/lobby/cache/`

## Deployment

The cache persists across deployments - only the symlink is recreated during `lobby update`.

## File Examples

Common cache files:
- `/opt/lobby/cache/players.json` - Player statistics
- `/opt/lobby/cache/schedule.json` - Game schedule  
- `/opt/lobby/cache/news.json` - News updates
- `/opt/lobby/cache/standings.json` - League standings

## Updates

Cache files can be updated independently of the Vue application. Changes are immediately available to the browser (subject to browser caching).