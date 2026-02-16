/**
 * @file api.ts
 * @description API client and service functions for the Research AI Assistant.
 * Contains axios instance configuration and API call wrappers.
 * Currently uses mock data - actual API implementation pending.
 */

import axios from 'axios';
import type { EntitySuggestion } from './types';

/**
 * Configured axios instance for API calls.
 * Base URL is determined by VITE_API_URL environment variable.
 */
const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL || "http://localhost:8000"
});

/**
 * Searches for entities (persons or organizations) based on a query string.
 * @param query - Search query to match against entity names
 * @param _types - Entity types to include in search (default: both)
 * @param _limit - Maximum number of results to return (default: 10)
 * @returns Promise resolving to array of matching entity suggestions
 * 
 * @todo Implement actual API call: GET /api/search?q=<query>&types=person,organization&limit=10
 */
export const searchEntities = async (
  query: string,
  _types: string[] = ['person', 'organization'],
  _limit: number = 10
): Promise<EntitySuggestion[]> => {
  // TODO: Implement actual API call
  // GET /api/search?q=<query>&types=person,organization&limit=10
  return getMockSuggestions(query);
};

/**
 * Returns mock entity suggestions for development/testing.
 * Filters mock data based on query matching label or extra field.
 * @param query - Search query to filter mock data
 * @returns Filtered array of mock entity suggestions
 */
const getMockSuggestions = (query: string): EntitySuggestion[] => {
  const mockData: EntitySuggestion[] = [
    { id: 'pure:org:1', type: 'organization', label: 'Faculty of Science', extra: 'Utrecht University' },
    { id: 'pure:org:2', type: 'organization', label: 'Department of Computer Science', extra: 'Faculty of Science' },
    { id: 'pure:org:3', type: 'organization', label: 'Chair of Petrology', extra: 'Faculty of Geosciences' },
    { id: 'pure:person:1', type: 'person', label: 'Dr. Jan de Vries', extra: 'Computer Science' },
    { id: 'pure:person:2', type: 'person', label: 'Prof. Maria van den Berg', extra: 'Faculty of Science' },
    { id: 'pure:person:3', type: 'person', label: 'Dr. Peter Jansen', extra: 'Petrology' },
  ];

  const lowerQuery = query.toLowerCase();
  return mockData.filter(
    item => 
      item.label.toLowerCase().includes(lowerQuery) ||
      item.extra?.toLowerCase().includes(lowerQuery)
  );
};

export default api;
