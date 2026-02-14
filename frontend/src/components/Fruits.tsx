import { useEffect, useState } from 'react';
import api, { getAuthError } from '../api';
import AddFruitForm from './AddFruitForm';

interface Fruit {
  name: string;
}

interface HealthStatus {
  status: string;
  service: string;
  time: string;
  fruit_count: number;
}

const FruitList = () => {
  const [fruits, setFruits] = useState<Fruit[]>([]);
  const [health, setHealth] = useState<HealthStatus | null>(null);
  const [backendError, setBackendError] = useState<string | null>(null);
  const [lastAction, setLastAction] = useState<string>('');

  const checkHealth = async () => {
    try {
      const response = await api.get('/health');
      setHealth(response.data);
      setBackendError(null);
    } catch (error) {
      setHealth(null);
      setBackendError(getAuthError() || 'Cannot reach backend');
    }
  };

  const fetchFruits = async () => {
    try {
      const response = await api.get('/fruits');
      setFruits(response.data.fruits);
      setBackendError(null);
      setLastAction(`Fetched ${response.data.fruits.length} fruit(s) from backend`);
    } catch (error) {
      console.error("Error fetching fruits", error);
      setBackendError(getAuthError() || 'Failed to fetch fruits');
    }
  };

  const addFruit = async (fruitName: string) => {
    try {
      const response = await api.post('/fruits', { name: fruitName });
      setLastAction(`Added "${fruitName}" — backend now has ${response.data.total} fruit(s)`);
      setBackendError(null);
      fetchFruits();
      checkHealth();
    } catch (error) {
      console.error("Error adding fruit", error);
      setBackendError(getAuthError() || 'Failed to add fruit');
    }
  };

  const clearFruits = async () => {
    try {
      await api.delete('/fruits');
      setLastAction('Cleared all fruits from backend');
      setBackendError(null);
      fetchFruits();
      checkHealth();
    } catch (error) {
      console.error("Error clearing fruits", error);
      setBackendError(getAuthError() || 'Failed to clear fruits');
    }
  };

  useEffect(() => {
    checkHealth();
    fetchFruits();
    const interval = setInterval(checkHealth, 10000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div>
      <div className="status-box">
        <h3>Backend Connection</h3>
        {backendError ? (
          <div className="status-badge status-error">{backendError}</div>
        ) : health ? (
          <div className="status-badge status-ok">
            Connected to {health.service}
          </div>
        ) : (
          <div className="status-badge status-loading">Checking...</div>
        )}
        {health && (
          <div className="status-details">
            Server time: {new Date(health.time).toLocaleTimeString()} | Fruits stored: {health.fruit_count}
          </div>
        )}
      </div>

      {lastAction && (
        <div className="last-action">
          {lastAction}
        </div>
      )}

      <h2>Fruits ({fruits.length})</h2>
      {fruits.length === 0 ? (
        <p className="empty-message">No fruits yet — add one below!</p>
      ) : (
        <ul className="fruit-list">
          {fruits.map((fruit, index) => (
            <li key={index}>{fruit.name}</li>
          ))}
        </ul>
      )}
      <AddFruitForm addFruit={addFruit} />
      {fruits.length > 0 && (
        <button className="clear-btn" onClick={clearFruits}>Clear All</button>
      )}
    </div>
  );
};

export default FruitList;
